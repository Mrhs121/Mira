import AppKit
import MiraCore
import QuartzCore

final class ImageCanvasView: NSView {
    private let imageLayer = CALayer()
    private let spinner = NSProgressIndicator()
    private let placeholderLabel = NSTextField(labelWithString: "")

    private(set) var image: CGImage?
    private(set) var zoom: CGFloat = 1

    var isAtFit: Bool {
        guard image != nil else { return false }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let isCentered = hypot(imageLayer.position.x - center.x, imageLayer.position.y - center.y) < 1.0
        return abs(zoom - fitScale) < 0.0001 && isCentered
    }

    var displayedPixelSize: CGSize {
        guard let image else { return .zero }
        return CGSize(width: image.width, height: image.height)
    }
    private var fitScale: CGFloat = 1
    private var imagePixelSize: CGSize = .zero
    private var hasDetail = false
    private var didRequestDetail = false
    private var dragging = false
    private var lastDragPoint: CGPoint?

    private var animationFrames: [CGImage] = []
    private var animationDurations: [TimeInterval] = []
    private var animationFrameIndex = 0
    private var animationLoopCount = 0
    private var animationLoopsCompleted = 0
    private var animationTimer: Timer?

    var onZoomChanged: ((CGFloat) -> Void)?
    var onNeedsDetail: (() -> Void)?
    var onContextMenu: (() -> NSMenu?)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.075, alpha: 1).cgColor

        imageLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        imageLayer.contentsGravity = .resizeAspect
        imageLayer.magnificationFilter = .linear
        imageLayer.minificationFilter = .trilinear
        imageLayer.contentsScale = window?.backingScaleFactor ?? 2
        imageLayer.isHidden = true
        layer?.addSublayer(imageLayer)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(spinner)

        placeholderLabel.font = .systemFont(ofSize: 11)
        placeholderLabel.textColor = NSColor(calibratedWhite: 0.42, alpha: 1)
        placeholderLabel.alignment = .center
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
            placeholderLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            placeholderLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 10)
        ])
    }

    override func layout() {
        super.layout()
        let wasFit = image != nil && abs(zoom - fitScale) < 0.0001
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        imageLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()

        if wasFit {
            fit(animated: false)
        } else {
            fitScale = computeFitScale()
            applyTransform()
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        imageLayer.contentsScale = window?.backingScaleFactor ?? 2
    }

    func showPlaceholder(pixelSize: CGSize?) {
        stopAnimation()
        image = nil
        hasDetail = false
        didRequestDetail = false
        imageLayer.contents = nil
        imageLayer.isHidden = true
        if let pixelSize, pixelSize.width > 0, pixelSize.height > 0 {
            placeholderLabel.stringValue = "\(Int(pixelSize.width)) × \(Int(pixelSize.height)) · 读取中…"
        } else {
            placeholderLabel.stringValue = "读取中…"
        }
        placeholderLabel.isHidden = false
        spinner.startAnimation(nil)
    }

    func display(image: CGImage, resetView: Bool = true) {
        stopAnimation()
        self.image = image
        imagePixelSize = CGSize(width: image.width, height: image.height)
        imageLayer.contents = image
        imageLayer.isHidden = false
        placeholderLabel.isHidden = true
        spinner.stopAnimation(nil)
        hasDetail = false
        didRequestDetail = false

        if resetView {
            fit(animated: false)
        } else {
            fitScale = computeFitScale()
            applyTransform()
        }
    }

    func display(animation: GIFAnimation, resetView: Bool = true) {
        stopAnimation()
        guard !animation.frames.isEmpty else { return }

        animationFrames = animation.frames
        animationDurations = animation.frameDurations
        animationLoopCount = animation.loopCount
        animationFrameIndex = 0
        animationLoopsCompleted = 0

        showAnimationFrame(at: 0, resetView: resetView)
        scheduleNextAnimationFrame()
    }

    func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        animationFrames.removeAll()
        animationDurations.removeAll()
        animationFrameIndex = 0
        animationLoopsCompleted = 0
    }

    private func showAnimationFrame(at index: Int, resetView: Bool) {
        guard animationFrames.indices.contains(index) else { return }
        let frame = animationFrames[index]
        image = frame
        imagePixelSize = CGSize(width: frame.width, height: frame.height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = frame
        imageLayer.isHidden = false
        CATransaction.commit()
        placeholderLabel.isHidden = true
        spinner.stopAnimation(nil)

        if resetView {
            fit(animated: false)
        } else {
            fitScale = computeFitScale()
            applyTransform()
        }
    }

    private func scheduleNextAnimationFrame() {
        animationTimer?.invalidate()
        guard !animationFrames.isEmpty else { return }
        let index = min(animationFrameIndex, max(0, animationDurations.count - 1))
        let delay = max(0.02, animationDurations.isEmpty ? 0.1 : animationDurations[index])

        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            self?.advanceAnimationFrame()
        }
        timer.tolerance = min(0.01, delay * 0.15)
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func advanceAnimationFrame() {
        guard !animationFrames.isEmpty else { return }
        let next = animationFrameIndex + 1
        if next < animationFrames.count {
            animationFrameIndex = next
            showAnimationFrame(at: next, resetView: false)
            scheduleNextAnimationFrame()
            return
        }

        if animationLoopCount == 0 || animationLoopsCompleted + 1 < animationLoopCount {
            animationLoopsCompleted += 1
            animationFrameIndex = 0
            showAnimationFrame(at: 0, resetView: false)
            scheduleNextAnimationFrame()
        } else {
            stopAnimation()
        }
    }

    func displayDetail(_ detail: CGImage) {
        guard image != nil, animationFrames.isEmpty else { return }
        imageLayer.contents = detail
        hasDetail = true
    }

    func clear() {
        stopAnimation()
        image = nil
        imageLayer.contents = nil
        imageLayer.isHidden = true
        placeholderLabel.stringValue = ""
        placeholderLabel.isHidden = true
        spinner.stopAnimation(nil)
        zoom = 1
        fitScale = 1
    }

    func fit(animated: Bool) {
        guard image != nil else { return }
        fitScale = computeFitScale()
        zoom = fitScale
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        applyLayer(scale: 1, position: center, animated: animated)
        onZoomChanged?(zoom)
    }

    func actualSize() {
        guard image != nil else { return }
        zoom = 1
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        applyLayer(scale: 1 / max(fitScale, 0.0001), position: center, animated: true)
        onZoomChanged?(zoom)
        requestDetailIfNeeded()
    }

    func toggleZoom(anchorInView: CGPoint? = nil) {
        guard image != nil else { return }
        let isFit = abs(zoom - fitScale) < 0.0001
        if isFit {
            zoom(to: 1, anchorInView: anchorInView ?? CGPoint(x: bounds.midX, y: bounds.midY))
        } else {
            fit(animated: true)
        }
    }

    func zoom(to newZoom: CGFloat, anchorInView: CGPoint) {
        guard image != nil else { return }
        let minZoom = max(fitScale * 0.5, 0.0001)
        let maxZoom: CGFloat = 8
        let target = min(max(newZoom, minZoom), maxZoom)
        guard abs(target - zoom) > 0.00001 else { return }

        let oldLayerScale = zoom / max(fitScale, 0.0001)
        let newLayerScale = target / max(fitScale, 0.0001)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let oldPosition = imageLayer.position
        let content = CGPoint(
            x: center.x + (anchorInView.x - oldPosition.x) / max(oldLayerScale, 0.0001),
            y: center.y + (anchorInView.y - oldPosition.y) / max(oldLayerScale, 0.0001)
        )
        let newPosition = CGPoint(
            x: anchorInView.x - (content.x - center.x) * newLayerScale,
            y: anchorInView.y - (content.y - center.y) * newLayerScale
        )

        zoom = target
        applyLayer(scale: newLayerScale, position: newPosition, animated: false)
        onZoomChanged?(zoom)
        requestDetailIfNeeded()
    }

    private func requestDetailIfNeeded() {
        guard !hasDetail, !didRequestDetail, zoom > fitScale * 1.5 else { return }
        didRequestDetail = true
        onNeedsDetail?()
    }

    private func applyLayer(scale: CGFloat, position: CGPoint, animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        if animated {
            CATransaction.setAnimationDuration(0.18)
        }
        imageLayer.transform = CATransform3DMakeScale(scale, scale, 1)
        imageLayer.position = position
        CATransaction.commit()
        clampPosition(scale: scale)
    }

    private func applyTransform() {
        let scale = zoom / max(fitScale, 0.0001)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.transform = CATransform3DMakeScale(scale, scale, 1)
        CATransaction.commit()
        clampPosition(scale: scale)
    }

    private func clampPosition(scale: CGFloat) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let scaledWidth = bounds.width * scale
        let scaledHeight = bounds.height * scale
        let marginX = min(120, max(40, bounds.width * 0.2))
        let marginY = min(120, max(40, bounds.height * 0.2))
        let maxX = max(bounds.width * 0.4, (scaledWidth + bounds.width) / 2 - marginX)
        let maxY = max(bounds.height * 0.4, (scaledHeight + bounds.height) / 2 - marginY)

        var position = imageLayer.position
        position.x = min(max(position.x, center.x - maxX), center.x + maxX)
        position.y = min(max(position.y, center.y - maxY), center.y + maxY)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.position = position
        CATransaction.commit()
    }

    private func computeFitScale() -> CGFloat {
        guard imagePixelSize.width > 0, imagePixelSize.height > 0,
              bounds.width > 0, bounds.height > 0 else {
            return 1
        }
        return min(bounds.width / imagePixelSize.width, bounds.height / imagePixelSize.height, 1)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        onContextMenu?() ?? super.menu(for: event)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.clickCount == 2 {
            if dragging {
                dragging = false
                lastDragPoint = nil
                NSCursor.pop()
            }
            toggleZoom(anchorInView: convert(event.locationInWindow, from: nil))
            return
        }
        guard image != nil else { return }
        dragging = true
        lastDragPoint = convert(event.locationInWindow, from: nil)
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging, image != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        let last = lastDragPoint ?? point
        lastDragPoint = point

        var position = imageLayer.position
        position.x += point.x - last.x
        position.y += point.y - last.y
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.position = position
        CATransaction.commit()
        clampPosition(scale: zoom / max(fitScale, 0.0001))
        onZoomChanged?(zoom)
    }

    override func mouseUp(with event: NSEvent) {
        if dragging {
            dragging = false
            lastDragPoint = nil
            NSCursor.pop()
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard image != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        let rawDelta: CGFloat
        let sensitivity: CGFloat
        if event.hasPreciseScrollingDeltas {
            rawDelta = event.scrollingDeltaY
            sensitivity = 0.01
        } else {
            rawDelta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY * 10
            sensitivity = 0.045
        }
        guard abs(rawDelta) > 0.001 else { return }
        let factor = exp(rawDelta * sensitivity)
        zoom(to: zoom * factor, anchorInView: point)
    }

    override func magnify(with event: NSEvent) {
        guard image != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        zoom(to: zoom * (1 + event.magnification), anchorInView: point)
    }
}
