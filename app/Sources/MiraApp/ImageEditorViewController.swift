import AppKit
import ImageIO
import UniformTypeIdentifiers
import MiraCore

enum EditorTool: Int {
    case text
    case rectangle
    case ellipse
    case line
    case crop
}

struct EditorAnnotation: Identifiable {
    enum Kind {
        case text(String)
        case rectangle
        case ellipse
        case line
    }

    let id: UUID
    /// Normalized image coordinates, origin top-left.
    var start: CGPoint
    var end: CGPoint
    var kind: Kind
    var color: NSColor
    /// Pixels in the source image.
    var lineWidth: CGFloat
    /// Pixels in the source image, used by text.
    var fontSize: CGFloat

    init(
        id: UUID = UUID(),
        kind: Kind,
        start: CGPoint,
        end: CGPoint,
        color: NSColor,
        lineWidth: CGFloat,
        fontSize: CGFloat
    ) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.color = color
        self.lineWidth = lineWidth
        self.fontSize = fontSize
    }

    var text: String? {
        if case .text(let value) = kind { return value }
        return nil
    }
}

// MARK: - Crop overlay

final class CropOverlayView: NSView {
    var imageRect: CGRect = .zero
    var cropViewRect: CGRect? {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let crop = cropViewRect,
              imageRect.width > 1, imageRect.height > 1,
              crop.width > 1, crop.height > 1 else { return }

        let outside = NSBezierPath(rect: imageRect)
        outside.append(NSBezierPath(rect: crop))
        outside.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.5).setFill()
        outside.fill()

        let border = NSBezierPath(rect: crop)
        border.lineWidth = 1.5
        border.setLineDash([6, 4], count: 2, phase: 0)
        NSColor.white.withAlphaComponent(0.95).setStroke()
        border.stroke()
    }
}

// MARK: - Canvas

final class EditorCanvasView: NSView {
    var image: CGImage? {
        didSet {
            if let image {
                nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            } else {
                nsImage = nil
            }
            updateCropOverlay()
            needsDisplay = true
        }
    }
    var annotations: [EditorAnnotation] = [] {
        didSet { needsDisplay = true }
    }
    var tool: EditorTool = .rectangle {
        didSet { updateCropOverlay() }
    }
    var annotationColor: NSColor = .systemRed
    var lineWidth: CGFloat = 16
    var renderMode = false {
        didSet { updateCropOverlay() }
    }

    private(set) var cropRect: CGRect?
    private(set) var selectedID: UUID?
    private(set) var editingTextID: UUID?

    var onAnnotationsChanged: (() -> Void)?
    var onCropChanged: (() -> Void)?
    var onSelectionChanged: (() -> Void)?

    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var movingID: UUID?
    private var moveLastPoint: CGPoint?
    private var nsImage: NSImage?
    private let cropOverlay = CropOverlayView()
    private var textOverlay: TextOverlayView?
    private var editingOriginalText = ""
    private var finishingText = false
    private var lastTextCommitAt: TimeInterval = 0

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        cropOverlay.autoresizingMask = [.width, .height]
        addSubview(cropOverlay)
    }

    override func layout() {
        super.layout()
        cropOverlay.frame = bounds
        updateCropOverlay()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var hasCrop: Bool { cropRect != nil }

    var selectedAnnotation: EditorAnnotation? {
        guard let selectedID else { return nil }
        return annotations.first { $0.id == selectedID }
    }

    var imageRect: CGRect {
        guard let image else { return .zero }
        let padding: CGFloat = renderMode ? 0 : 20
        let available = bounds.insetBy(dx: padding, dy: padding)
        guard available.width > 0, available.height > 0 else { return .zero }
        let scale = min(available.width / CGFloat(image.width), available.height / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        return CGRect(
            x: available.midX - size.width / 2,
            y: available.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        if renderMode {
            context.clear(bounds)
        } else {
            context.setFillColor(NSColor(calibratedWhite: 0.075, alpha: 1).cgColor)
            context.fill(bounds)
        }

        guard image != nil else {
            drawLoading(in: bounds)
            return
        }

        let rect = imageRect
        guard rect.width > 0, rect.height > 0 else { return }
        let cropDragging = !renderMode && tool == .crop && dragStart != nil
        nsImage?.draw(
            in: rect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: cropDragging ? NSImageInterpolation.medium : NSImageInterpolation.high]
        )

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        for annotation in annotations where annotation.id != editingTextID {
            draw(annotation, in: rect)
        }
        if let draft = draftAnnotation(in: rect) {
            draw(draft, in: rect)
        }
        if !renderMode, let selectedAnnotation, selectedAnnotation.id != editingTextID {
            drawSelection(selectedAnnotation, in: rect)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawLoading(in rect: NSRect) {
        let text = "正在准备编辑…" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor(calibratedWhite: 0.5, alpha: 1)
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            withAttributes: attributes
        )
    }

    private func draw(_ annotation: EditorAnnotation, in rect: CGRect) {
        let start = viewPoint(annotation.start, in: rect)
        let end = viewPoint(annotation.end, in: rect)
        let scale = rect.width / CGFloat(image?.width ?? 1)
        let width = max(1.5, annotation.lineWidth * scale)

        switch annotation.kind {
        case .text(let string):
            let font = textFont(for: annotation, in: rect)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: annotation.color,
                .strokeColor: NSColor.black.withAlphaComponent(0.65),
                .strokeWidth: -2.0
            ]
            NSAttributedString(string: string, attributes: attributes).draw(at: start)
        case .rectangle:
            let box = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            let path = NSBezierPath(rect: box)
            path.lineWidth = width
            annotation.color.setStroke()
            path.stroke()
        case .ellipse:
            let box = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            let path = NSBezierPath(ovalIn: box)
            path.lineWidth = width
            annotation.color.setStroke()
            path.stroke()
        case .line:
            let path = NSBezierPath()
            path.move(to: start)
            path.line(to: end)
            path.lineWidth = width
            path.lineCapStyle = .round
            annotation.color.setStroke()
            path.stroke()
        }
    }

    private func drawSelection(_ annotation: EditorAnnotation, in rect: CGRect) {
        guard let box = viewBounds(annotation, in: rect) else { return }
        let selection = box.insetBy(dx: -5, dy: -5)
        let path = NSBezierPath(rect: selection)
        path.lineWidth = 1.2
        path.setLineDash([5, 3], count: 2, phase: 0)
        NSColor.systemBlue.withAlphaComponent(0.95).setStroke()
        path.stroke()

        for point in [
            CGPoint(x: selection.minX, y: selection.minY),
            CGPoint(x: selection.maxX, y: selection.minY),
            CGPoint(x: selection.minX, y: selection.maxY),
            CGPoint(x: selection.maxX, y: selection.maxY)
        ] {
            let handle = CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)
            NSColor.white.setFill()
            NSBezierPath(ovalIn: handle).fill()
            NSColor.systemBlue.setStroke()
            let outline = NSBezierPath(ovalIn: handle)
            outline.lineWidth = 1
            outline.stroke()
        }
    }

    private func draftAnnotation(in rect: CGRect) -> EditorAnnotation? {
        guard let dragStart, let dragCurrent, tool != .crop, tool != .text else { return nil }
        let kind: EditorAnnotation.Kind
        switch tool {
        case .rectangle: kind = .rectangle
        case .ellipse: kind = .ellipse
        case .line: kind = .line
        case .text, .crop: return nil
        }
        return EditorAnnotation(
            kind: kind,
            start: dragStart,
            end: dragCurrent,
            color: annotationColor,
            lineWidth: image.map { annotationLineWidth(for: $0) } ?? lineWidth,
            fontSize: 0
        )
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let wasEditingText = textOverlay != nil
        window?.makeFirstResponder(self)
        guard image != nil, imageRect.width > 0 else { return }
        let point = convert(event.locationInWindow, from: nil)

        if !imageRect.contains(point) {
            finishTextEditing(commit: true)
            select(nil)
            return
        }

        if tool == .text, !wasEditingText,
           ProcessInfo.processInfo.systemUptime - lastTextCommitAt < 0.18,
           annotation(at: point, in: imageRect) == nil {
            return
        }
        if tool == .text, wasEditingText || textOverlay != nil {
            finishTextEditing(commit: true)
            return
        }
        if textOverlay != nil {
            finishTextEditing(commit: true)
        }

        if tool == .text {
            if let hit = annotation(at: point, in: imageRect) {
                if case .text = hit.kind, event.clickCount >= 2 {
                    beginTextEditing(existing: hit)
                } else {
                    select(hit.id)
                    movingID = hit.id
                    moveLastPoint = point
                }
            } else {
                beginTextEditing(at: normalizedPoint(point))
            }
            return
        }

        let normalized = normalizedPoint(point)
        if tool == .crop {
            select(nil)
            dragStart = normalized
            dragCurrent = normalized
            updateCropOverlay()
            return
        }

        if let hit = annotation(at: point, in: imageRect) {
            select(hit.id)
            movingID = hit.id
            moveLastPoint = point
            return
        }

        select(nil)
        dragStart = normalized
        dragCurrent = normalized
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if tool == .crop, dragStart != nil {
            guard image != nil, imageRect.contains(point) else { return }
            dragCurrent = normalizedPoint(point)
            updateCropOverlay()
            return
        }

        if let movingID, let last = moveLastPoint {
            guard imageRect.width > 0 else { return }
            let delta = CGSize(
                width: (point.x - last.x) / imageRect.width,
                height: (point.y - last.y) / imageRect.height
            )
            move(id: movingID, by: delta)
            moveLastPoint = point
            return
        }

        guard let start = dragStart, let image, imageRect.contains(point) else { return }
        var next = normalizedPoint(point)

        if event.modifierFlags.contains(.shift) {
            let dxPx = (next.x - start.x) * CGFloat(image.width)
            let dyPx = (next.y - start.y) * CGFloat(image.height)
            if tool == .line {
                let length = hypot(dxPx, dyPx)
                let angle = atan2(dyPx, dxPx)
                let snapped = (angle / (.pi / 4)).rounded() * (.pi / 4)
                next = CGPoint(
                    x: start.x + cos(snapped) * length / CGFloat(image.width),
                    y: start.y + sin(snapped) * length / CGFloat(image.height)
                )
            } else if tool == .rectangle || tool == .ellipse {
                let side = max(abs(dxPx), abs(dyPx))
                next = CGPoint(
                    x: start.x + (dxPx < 0 ? -side : side) / CGFloat(image.width),
                    y: start.y + (dyPx < 0 ? -side : side) / CGFloat(image.height)
                )
            }
        }

        dragCurrent = next
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if movingID != nil {
            movingID = nil
            moveLastPoint = nil
            onAnnotationsChanged?()
            return
        }

        guard let start = dragStart, let end = dragCurrent else { return }
        dragStart = nil
        dragCurrent = nil

        if tool == .crop {
            let rect = normalizedRect(start, end)
            if rect.width * imageRect.width >= 20, rect.height * imageRect.height >= 20 {
                cropRect = rect
                onCropChanged?()
            }
            updateCropOverlay()
        } else if let image {
            let distance = hypot(
                (end.x - start.x) * imageRect.width,
                (end.y - start.y) * imageRect.height
            )
            if distance >= 4 {
                let kind: EditorAnnotation.Kind
                switch tool {
                case .rectangle: kind = .rectangle
                case .ellipse: kind = .ellipse
                case .line: kind = .line
                case .text, .crop: return
                }
                let annotation = EditorAnnotation(
                    kind: kind,
                    start: start,
                    end: end,
                    color: annotationColor,
                    lineWidth: annotationLineWidth(for: image),
                    fontSize: 0
                )
                annotations.append(annotation)
                select(annotation.id)
                onAnnotationsChanged?()
            }
        }
        needsDisplay = true
    }

    private func move(id: UUID, by delta: CGSize) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        var annotation = annotations[index]
        let bounds = CGRect(
            x: min(annotation.start.x, annotation.end.x),
            y: min(annotation.start.y, annotation.end.y),
            width: abs(annotation.start.x - annotation.end.x),
            height: abs(annotation.start.y - annotation.end.y)
        )
        var dx = delta.width
        var dy = delta.height
        if bounds.minX + dx < 0 { dx = -bounds.minX }
        if bounds.maxX + dx > 1 { dx = 1 - bounds.maxX }
        if bounds.minY + dy < 0 { dy = -bounds.minY }
        if bounds.maxY + dy > 1 { dy = 1 - bounds.maxY }
        annotation.start.x += dx
        annotation.start.y += dy
        annotation.end.x += dx
        annotation.end.y += dy
        annotations[index] = annotation
        needsDisplay = true
    }

    func deleteSelected() {
        guard let selectedID else { return }
        annotations.removeAll { $0.id == selectedID }
        select(nil)
        onAnnotationsChanged?()
        needsDisplay = true
    }

    func clearAllAnnotations() {
        finishTextEditing(commit: true)
        annotations = []
        cropRect = nil
        updateCropOverlay()
        select(nil)
        onCropChanged?()
        onAnnotationsChanged?()
        needsDisplay = true
    }

    func cancelCrop() {
        guard cropRect != nil else { return }
        cropRect = nil
        updateCropOverlay()
        onCropChanged?()
        needsDisplay = true
    }

    func applyStyle(color: NSColor, baseLineWidth: CGFloat) {
        annotationColor = color
        lineWidth = baseLineWidth
        textOverlay?.setTextColor(color)
        guard let selectedID,
              let index = annotations.firstIndex(where: { $0.id == selectedID }) else { return }
        annotations[index].color = color
        if let image, annotations[index].text == nil {
            annotations[index].lineWidth = annotationLineWidth(for: image)
        }
        needsDisplay = true
    }

    // MARK: - Text editing

    private func beginTextEditing(at normalized: CGPoint) {
        guard let image else { return }
        finishTextEditing(commit: true)
        let annotation = EditorAnnotation(
            kind: .text(""),
            start: normalized,
            end: normalized,
            color: annotationColor,
            lineWidth: annotationLineWidth(for: image),
            fontSize: max(30, min(140, CGFloat(image.width) / 45))
        )
        annotations.append(annotation)
        editingOriginalText = ""
        beginOverlay(for: annotation)
        onAnnotationsChanged?()
    }

    private func beginTextEditing(existing: EditorAnnotation) {
        guard existing.text != nil else { return }
        finishTextEditing(commit: true)
        editingOriginalText = existing.text ?? ""
        beginOverlay(for: existing)
    }

    private func beginOverlay(for annotation: EditorAnnotation) {
        guard let image, imageRect.width > 0 else { return }
        editingTextID = annotation.id
        select(annotation.id)
        needsDisplay = true

        let scale = imageRect.width / CGFloat(image.width)
        let font = NSFont.systemFont(
            ofSize: max(9, annotation.fontSize * scale),
            weight: .semibold
        )
        let overlay = TextOverlayView(
            text: annotation.text ?? "",
            font: font,
            color: annotation.color
        )
        let origin = viewPoint(annotation.start, in: imageRect)
        overlay.frame.origin = CGPoint(
            x: origin.x - TextOverlayView.textInset.x,
            y: origin.y - TextOverlayView.textInset.y
        )
        overlay.onTextChanged = { [weak self] text in
            self?.updateEditingText(text)
        }
        overlay.onCommit = { [weak self] in
            self?.finishTextEditing(commit: true)
        }
        overlay.onCancel = { [weak self] in
            self?.finishTextEditing(commit: false)
        }
        overlay.onMove = { [weak self] delta in
            self?.moveEditingText(by: delta)
        }
        addSubview(overlay)
        textOverlay = overlay
        DispatchQueue.main.async {
            overlay.focus()
        }
    }

    private func updateEditingText(_ text: String) {
        guard let id = editingTextID,
              let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[index].kind = .text(text)
        textOverlay?.updateSize()
        needsDisplay = true
    }

    private func moveEditingText(by delta: CGSize) {
        guard let id = editingTextID,
              let index = annotations.firstIndex(where: { $0.id == id }),
              imageRect.width > 0 else { return }
        var annotation = annotations[index]
        annotation.start.x = min(max(annotation.start.x + delta.width / imageRect.width, 0), 1)
        annotation.start.y = min(max(annotation.start.y + delta.height / imageRect.height, 0), 1)
        annotation.end = annotation.start
        annotations[index] = annotation

        if let overlay = textOverlay {
            let origin = viewPoint(annotation.start, in: imageRect)
            overlay.frame.origin = CGPoint(
                x: origin.x - TextOverlayView.textInset.x,
                y: origin.y - TextOverlayView.textInset.y
            )
        }
        needsDisplay = true
    }

    var isEditingText: Bool { textOverlay != nil }

    var textEditorHasMarkedText: Bool {
        (textOverlay?.textField.currentEditor() as? NSTextView)?.hasMarkedText() ?? false
    }

    func commitActiveText() {
        finishTextEditing(commit: true)
    }

    private func finishTextEditing(commit: Bool) {
        guard !finishingText, let id = editingTextID, let overlay = textOverlay else { return }
        finishingText = true
        overlay.prepareForRemoval()

        let text = overlay.textField.stringValue
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = annotations.firstIndex(where: { $0.id == id }) {
            if commit, !trimmed.isEmpty {
                annotations[index].kind = .text(text)
                select(id)
            } else if !commit, !editingOriginalText.isEmpty {
                annotations[index].kind = .text(editingOriginalText)
                select(id)
            } else {
                annotations.remove(at: index)
                select(nil)
            }
        }

        overlay.removeFromSuperview()
        textOverlay = nil
        editingTextID = nil
        editingOriginalText = ""
        lastTextCommitAt = ProcessInfo.processInfo.systemUptime
        finishingText = false
        needsDisplay = true
        onAnnotationsChanged?()
        onSelectionChanged?()
    }

    // MARK: - Crop / rotate

    @discardableResult
    func applyCrop() -> Bool {
        finishTextEditing(commit: true)
        guard let image, let crop = cropRect else { return false }
        let pxX = Int(round(crop.minX * CGFloat(image.width)))
        let pxY = Int(round(crop.minY * CGFloat(image.height)))
        let pxW = Int(round(crop.width * CGFloat(image.width)))
        let pxH = Int(round(crop.height * CGFloat(image.height)))
        guard pxW >= 16, pxH >= 16 else { return false }

        let cropPixels = CGRect(x: pxX, y: pxY, width: pxW, height: pxH)
        guard let cropped = croppedImage(image, to: cropPixels) else { return false }
        let annotationScale = CGFloat(cropped.width) / CGFloat(image.width)
        let mapped = annotations.map { annotation -> EditorAnnotation in
            var copy = annotation
            copy.start = CGPoint(
                x: (annotation.start.x - crop.minX) / crop.width,
                y: (annotation.start.y - crop.minY) / crop.height
            )
            copy.end = CGPoint(
                x: (annotation.end.x - crop.minX) / crop.width,
                y: (annotation.end.y - crop.minY) / crop.height
            )
            copy.lineWidth *= annotationScale
            copy.fontSize *= annotationScale
            return copy
        }
        self.image = cropped
        self.annotations = mapped
        self.cropRect = nil
        updateCropOverlay()
        onAnnotationsChanged?()
        onCropChanged?()
        needsDisplay = true
        return true
    }

    func rotate(clockwise: Bool) {
        finishTextEditing(commit: true)
        guard let image, let rotated = rotated(image, clockwise: clockwise) else { return }
        annotations = annotations.map { annotation in
            var copy = annotation
            copy.start = rotatedPoint(annotation.start, clockwise: clockwise)
            copy.end = rotatedPoint(annotation.end, clockwise: clockwise)
            return copy
        }
        cropRect = nil
        updateCropOverlay()
        self.image = rotated
        onAnnotationsChanged?()
        onCropChanged?()
        onSelectionChanged?()
        needsDisplay = true
    }

    // MARK: - Render

    func renderedImage() -> CGImage? {
        guard let image else { return nil }
        let renderView = EditorCanvasView(frame: NSRect(x: 0, y: 0, width: image.width, height: image.height))
        renderView.renderMode = true
        renderView.image = image
        renderView.annotations = annotations
        renderView.layoutSubtreeIfNeeded()
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: image.width,
            pixelsHigh: image.height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        renderView.cacheDisplay(in: renderView.bounds, to: rep)
        guard let rendered = rep.cgImage else { return nil }
        if rendered.width == image.width, rendered.height == image.height {
            return rendered
        }
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: rendered.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return rendered }
        context.interpolationQuality = .high
        context.draw(rendered, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    // MARK: - Crop preview

    private var cropPreviewRect: CGRect? {
        guard tool == .crop else { return nil }
        if let dragStart, let dragCurrent {
            return normalizedRect(dragStart, dragCurrent)
        }
        return cropRect
    }

    private func updateCropOverlay() {
        cropOverlay.frame = bounds
        guard !renderMode, tool == .crop, imageRect.width > 1, imageRect.height > 1,
              let preview = cropPreviewRect,
              preview.width > 0.001, preview.height > 0.001 else {
            cropOverlay.cropViewRect = nil
            cropOverlay.isHidden = true
            return
        }
        cropOverlay.imageRect = imageRect
        cropOverlay.cropViewRect = viewRect(preview, in: imageRect)
        cropOverlay.isHidden = false
        cropOverlay.needsDisplay = true
    }

    // MARK: - Geometry

    private func normalizedPoint(_ point: CGPoint) -> CGPoint {
        let rect = imageRect
        guard rect.width > 0, rect.height > 0 else { return .zero }
        return CGPoint(
            x: min(max((point.x - rect.minX) / rect.width, 0), 1),
            y: min(max((point.y - rect.minY) / rect.height, 0), 1)
        )
    }

    private func viewPoint(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
    }

    private func viewRect(_ normalized: CGRect, in rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX + normalized.minX * rect.width,
            y: rect.minY + normalized.minY * rect.height,
            width: normalized.width * rect.width,
            height: normalized.height * rect.height
        )
    }

    private func normalizedRect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(a.x - b.x),
            height: abs(a.y - b.y)
        )
    }

    private func rotatedPoint(_ point: CGPoint, clockwise: Bool) -> CGPoint {
        clockwise
            ? CGPoint(x: 1 - point.y, y: point.x)
            : CGPoint(x: point.y, y: 1 - point.x)
    }

    private func annotationLineWidth(for image: CGImage) -> CGFloat {
        max(2, lineWidth * max(1, CGFloat(image.width) / 1600))
    }

    private func textFont(for annotation: EditorAnnotation, in rect: CGRect) -> NSFont {
        NSFont.systemFont(
            ofSize: max(8, annotation.fontSize * rect.width / CGFloat(image?.width ?? 1)),
            weight: .semibold
        )
    }

    private func viewBounds(_ annotation: EditorAnnotation, in rect: CGRect) -> CGRect? {
        let start = viewPoint(annotation.start, in: rect)
        let end = viewPoint(annotation.end, in: rect)
        switch annotation.kind {
        case .text(let string):
            guard !string.isEmpty else { return CGRect(x: start.x, y: start.y, width: 24, height: 20) }
            let attributes: [NSAttributedString.Key: Any] = [.font: textFont(for: annotation, in: rect)]
            let size = NSAttributedString(string: string, attributes: attributes).size()
            return CGRect(x: start.x, y: start.y, width: size.width, height: size.height)
        case .rectangle, .ellipse, .line:
            return CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
        }
    }

    private func annotation(at point: CGPoint, in rect: CGRect) -> EditorAnnotation? {
        for annotation in annotations.reversed() where annotation.id != editingTextID {
            guard let bounds = viewBounds(annotation, in: rect) else { continue }
            if case .line = annotation.kind {
                let start = viewPoint(annotation.start, in: rect)
                let end = viewPoint(annotation.end, in: rect)
                if distance(from: point, toSegmentFrom: start, to: end) <= 10 {
                    return annotation
                }
            } else if bounds.insetBy(dx: -8, dy: -8).contains(point) {
                return annotation
            }
        }
        return nil
    }

    private func textAnnotation(at point: CGPoint) -> EditorAnnotation? {
        for annotation in annotations.reversed() where annotation.text != nil && annotation.id != editingTextID {
            guard let bounds = viewBounds(annotation, in: imageRect) else { continue }
            if bounds.insetBy(dx: -8, dy: -8).contains(point) {
                return annotation
            }
        }
        return nil
    }

    private func distance(from point: CGPoint, toSegmentFrom a: CGPoint, to b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - a.x, point.y - a.y) }
        let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared))
        let projection = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return hypot(point.x - projection.x, point.y - projection.y)
    }

    private func croppedImage(_ image: CGImage, to rect: CGRect) -> CGImage? {
        let pixelRect = CGRect(
            x: Int(rect.minX),
            y: Int(rect.minY),
            width: Int(rect.width),
            height: Int(rect.height)
        )
        guard pixelRect.width > 0, pixelRect.height > 0 else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let clipped = pixelRect.intersection(bounds)
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return nil }
        return image.cropping(to: clipped)
    }

    private func rotated(_ image: CGImage, clockwise: Bool) -> CGImage? {
        let width = image.width
        let height = image.height
        let newWidth = height
        let newHeight = width
        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.translateBy(x: CGFloat(newWidth) / 2, y: CGFloat(newHeight) / 2)
        context.rotate(by: clockwise ? -.pi / 2 : .pi / 2)
        context.draw(
            image,
            in: CGRect(
                x: -CGFloat(width) / 2,
                y: -CGFloat(height) / 2,
                width: CGFloat(width),
                height: CGFloat(height)
            )
        )
        return context.makeImage()
    }

    private func select(_ id: UUID?) {
        guard selectedID != id else { return }
        selectedID = id
        needsDisplay = true
        onSelectionChanged?()
    }

}

// MARK: - Preview-style Markup Toolbar Controls

final class MarkupToolbarButton: NSButton {
    enum Icon {
        case textBox
        case rectangle
        case ellipse
        case line
        case crop
        case symbol(String)
    }

    let icon: Icon
    var buttonTitle: String? {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    var isActiveTool: Bool = false {
        didSet { needsDisplay = true }
    }
    var isAccentPill: Bool = false {
        didSet { needsDisplay = true }
    }

    private var isHovered = false {
        didSet {
            if oldValue != isHovered {
                needsDisplay = true
            }
        }
    }
    private var trackingAreaRef: NSTrackingArea?

    init(icon: Icon, title: String? = nil, tooltip: String, target: AnyObject?, action: Selector) {
        self.icon = icon
        self.buttonTitle = title
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        self.title = ""
        focusRingType = .none
        setButtonType(.momentaryChange)
        self.target = target
        self.action = action
        self.toolTip = tooltip
        setAccessibilityLabel(tooltip)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        if let buttonTitle, !buttonTitle.isEmpty {
            let font = NSFont.systemFont(ofSize: 11.5, weight: isAccentPill ? .semibold : .medium)
            let textWidth = (buttonTitle as NSString).size(withAttributes: [.font: font]).width
            let iconSpace: CGFloat = {
                if case .symbol(let name) = icon, name.isEmpty { return 0 }
                return 18
            }()
            return NSSize(width: ceil(textWidth) + iconSpace + 18, height: 26)
        }
        return NSSize(width: 30, height: 26)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func draw(_ dirtyRect: NSRect) {
        let isPressed = isHighlighted && isEnabled
        let pillRect = bounds.insetBy(dx: 1, dy: 1)

        if isAccentPill {
            let bg: NSColor
            if !isEnabled {
                bg = NSColor(calibratedWhite: 0.22, alpha: 0.7)
            } else if isPressed {
                bg = NSColor(srgbRed: 0.05, green: 0.45, blue: 0.90, alpha: 1)
            } else if isHovered {
                bg = NSColor(srgbRed: 0.14, green: 0.58, blue: 1.0, alpha: 1)
            } else {
                bg = NSColor(srgbRed: 0.08, green: 0.52, blue: 0.98, alpha: 1)
            }
            let path = NSBezierPath(roundedRect: pillRect, xRadius: 5.5, yRadius: 5.5)
            bg.setFill()
            path.fill()
        } else if isActiveTool {
            let alpha: CGFloat = isPressed ? 0.24 : (isHovered ? 0.18 : 0.14)
            let bg = NSColor(srgbRed: 0.10, green: 0.56, blue: 1.0, alpha: alpha)
            let path = NSBezierPath(roundedRect: pillRect, xRadius: 5, yRadius: 5)
            bg.setFill()
            path.fill()
        } else if isEnabled && (isPressed || isHovered) {
            let bg = NSColor(calibratedWhite: 1.0, alpha: isPressed ? 0.13 : 0.07)
            let path = NSBezierPath(roundedRect: pillRect, xRadius: 5, yRadius: 5)
            bg.setFill()
            path.fill()
        }

        let fgColor: NSColor
        if !isEnabled {
            fgColor = NSColor(calibratedWhite: 0.35, alpha: 1)
        } else if isAccentPill {
            fgColor = .white
        } else if isActiveTool {
            fgColor = NSColor(srgbRed: 0.16, green: 0.62, blue: 1.0, alpha: 1)
        } else if isHovered || isPressed {
            fgColor = NSColor(calibratedWhite: 0.92, alpha: 1)
        } else {
            fgColor = NSColor(calibratedWhite: 0.76, alpha: 1)
        }

        if let buttonTitle, !buttonTitle.isEmpty {
            drawIconAndTitle(title: buttonTitle, color: fgColor)
        } else {
            drawIcon(in: bounds, color: fgColor)
        }
    }

    private func drawIconAndTitle(title: String, color: NSColor) {
        let font = NSFont.systemFont(ofSize: 11.5, weight: isAccentPill ? .semibold : .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let textSize = (title as NSString).size(withAttributes: attrs)
        var hasSymbol = true
        if case .symbol(let name) = icon, name.isEmpty {
            hasSymbol = false
        }

        if hasSymbol {
            let totalWidth = 15 + 5 + textSize.width
            let startX = round((bounds.width - totalWidth) / 2)
            let iconRect = NSRect(x: startX, y: (bounds.height - 15) / 2, width: 15, height: 15)
            drawIcon(in: iconRect, color: color, symbolPointSize: 12)
            let textOrigin = NSPoint(
                x: startX + 20,
                y: round((bounds.height - textSize.height) / 2)
            )
            (title as NSString).draw(at: textOrigin, withAttributes: attrs)
        } else {
            let textOrigin = NSPoint(
                x: round((bounds.width - textSize.width) / 2),
                y: round((bounds.height - textSize.height) / 2)
            )
            (title as NSString).draw(at: textOrigin, withAttributes: attrs)
        }
    }

    private func drawIcon(in rect: NSRect, color: NSColor, symbolPointSize: CGFloat = 14) {
        color.setStroke()
        color.setFill()

        switch icon {
        case .textBox:
            // Matches macOS Preview's [字] markup icon
            let boxW: CGFloat = 18
            let boxH: CGFloat = 13
            let box = NSRect(
                x: round(rect.midX - boxW / 2),
                y: round(rect.midY - boxH / 2),
                width: boxW,
                height: boxH
            )
            let framePath = NSBezierPath(roundedRect: box, xRadius: 2, yRadius: 2)
            framePath.lineWidth = 1.3
            framePath.stroke()

            let handleSize: CGFloat = 2.4
            let leftHandle = NSRect(
                x: box.minX - handleSize / 2,
                y: box.midY - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
            let rightHandle = NSRect(
                x: box.maxX - handleSize / 2,
                y: box.midY - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
            NSBezierPath(rect: leftHandle).fill()
            NSBezierPath(rect: rightHandle).fill()

            let char = "字" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 8.5, weight: .bold),
                .foregroundColor: color
            ]
            let size = char.size(withAttributes: attrs)
            char.draw(
                at: NSPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2),
                withAttributes: attrs
            )

        case .rectangle:
            let box = NSRect(
                x: round(rect.midX - 7.5) + 0.5,
                y: round(rect.midY - 5.5) + 0.5,
                width: 15,
                height: 11
            )
            let path = NSBezierPath(roundedRect: box, xRadius: 1.8, yRadius: 1.8)
            path.lineWidth = 1.5
            path.stroke()

        case .ellipse:
            let box = NSRect(
                x: round(rect.midX - 7.5) + 0.5,
                y: round(rect.midY - 6) + 0.5,
                width: 15,
                height: 12
            )
            let path = NSBezierPath(ovalIn: box)
            path.lineWidth = 1.5
            path.stroke()

        case .line:
            let path = NSBezierPath()
            path.move(to: NSPoint(x: rect.midX - 6.5, y: rect.midY + 5.5))
            path.line(to: NSPoint(x: rect.midX + 6.5, y: rect.midY - 5.5))
            path.lineWidth = 1.65
            path.lineCapStyle = .round
            path.stroke()

        case .crop:
            drawSymbol("crop", in: rect, color: color, pointSize: symbolPointSize)

        case .symbol(let name):
            guard !name.isEmpty else { return }
            drawSymbol(name, in: rect, color: color, pointSize: symbolPointSize)
        }
    }

    private func drawSymbol(_ name: String, in rect: NSRect, color: NSColor, pointSize: CGFloat) {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
            .applying(.init(hierarchicalColor: color))
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil),
              let symbolImage = base.withSymbolConfiguration(config) else { return }
        let size = symbolImage.size
        let drawRect = NSRect(
            x: round(rect.midX - size.width / 2),
            y: round(rect.midY - size.height / 2),
            width: size.width,
            height: size.height
        )
        symbolImage.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}

final class LineWidthPopupButton: NSButton {
    var levels: [CGFloat] = [] {
        didSet {
            selectedIndex = min(max(selectedIndex, 0), max(levels.count - 1, 0))
            needsDisplay = true
        }
    }

    var selectedIndex: Int = 0 {
        didSet {
            setAccessibilityValue("\(selectedIndex + 1)")
            needsDisplay = true
        }
    }

    var onSelect: ((Int) -> Void)?

    private var isHovered = false {
        didSet {
            if oldValue != isHovered {
                needsDisplay = true
            }
        }
    }
    private var trackingAreaRef: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        bezelStyle = .regularSquare
        title = ""
        focusRingType = .none
        setButtonType(.momentaryChange)
        target = self
        action = #selector(openMenu)
        toolTip = "线条粗细"
        setAccessibilityLabel("线宽")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 42, height: 26)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func draw(_ dirtyRect: NSRect) {
        if isEnabled && (isHighlighted || isHovered) {
            let bg = NSColor(calibratedWhite: 1.0, alpha: isHighlighted ? 0.13 : 0.07)
            let pill = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5)
            bg.setFill()
            pill.fill()
        }

        // Matches Preview's line-style button: three horizontal bars of increasing thickness + downward chevron
        let fg: NSColor
        if !isEnabled {
            fg = NSColor(calibratedWhite: 0.35, alpha: 1)
        } else if isHovered || isHighlighted {
            fg = NSColor(calibratedWhite: 0.92, alpha: 1)
        } else {
            fg = NSColor(calibratedWhite: 0.76, alpha: 1)
        }
        fg.setFill()

        let barX: CGFloat = 6
        let barW: CGFloat = 15
        let topBar = NSRect(x: barX, y: round(bounds.midY - 6), width: barW, height: 1.3)
        let midBar = NSRect(x: barX, y: round(bounds.midY - 1.2), width: barW, height: 2.3)
        let botBar = NSRect(x: barX, y: round(bounds.midY + 3.5), width: barW, height: 3.6)
        NSBezierPath(roundedRect: topBar, xRadius: 0.6, yRadius: 0.6).fill()
        NSBezierPath(roundedRect: midBar, xRadius: 0.9, yRadius: 0.9).fill()
        NSBezierPath(roundedRect: botBar, xRadius: 1.0, yRadius: 1.0).fill()

        // Downward chevron (isFlipped == true in NSButton, so +y is down)
        let cx: CGFloat = bounds.width - 10.5
        let cy: CGFloat = bounds.midY + 0.5
        let chevron = NSBezierPath()
        chevron.move(to: NSPoint(x: cx - 3.2, y: cy - 1.6))
        chevron.line(to: NSPoint(x: cx, y: cy + 1.8))
        chevron.line(to: NSPoint(x: cx + 3.2, y: cy - 1.6))
        chevron.lineWidth = 1.4
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round
        let chevronColor = isEnabled
            ? NSColor(calibratedWhite: isHovered ? 0.85 : 0.64, alpha: 1)
            : NSColor(calibratedWhite: 0.32, alpha: 1)
        chevronColor.setStroke()
        chevron.stroke()
    }

    @objc private func openMenu() {
        guard !levels.isEmpty else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (index, value) in levels.enumerated() {
            let item = NSMenuItem()
            let view = LineWidthMenuItemView(index: index, value: value, isSelected: index == selectedIndex)
            view.onPick = { [weak self, weak menu] in
                guard let self else { return }
                self.selectedIndex = index
                menu?.cancelTracking()
                self.onSelect?(index)
            }
            item.view = view
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + 4), in: self)
    }
}

final class LineWidthMenuItemView: NSButton {
    let index: Int
    let value: CGFloat
    let isCurrent: Bool
    var onPick: (() -> Void)?

    private var isHovered = false {
        didSet {
            if oldValue != isHovered {
                needsDisplay = true
            }
        }
    }
    private var trackingAreaRef: NSTrackingArea?

    init(index: Int, value: CGFloat, isSelected: Bool = false) {
        self.index = index
        self.value = value
        self.isCurrent = isSelected
        super.init(frame: NSRect(x: 0, y: 0, width: 144, height: 28))
        isBordered = false
        title = ""
        focusRingType = .none
        setButtonType(.momentaryChange)
        target = self
        action = #selector(pick)
        toolTip = "线宽 \(index + 1)/6"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    @objc private func pick() {
        onPick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHovered || isCurrent {
            let pill = NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 2), xRadius: 5, yRadius: 5)
            if isHovered {
                NSColor.selectedContentBackgroundColor.withAlphaComponent(0.85).setFill()
            } else {
                NSColor.labelColor.withAlphaComponent(0.1).setFill()
            }
            pill.fill()
        }

        let strokeColor: NSColor = isHovered ? .white : .labelColor
        if isCurrent {
            let dot = NSRect(x: 11, y: bounds.midY - 2.5, width: 5, height: 5)
            (isHovered ? NSColor.white : NSColor.controlAccentColor).setFill()
            NSBezierPath(ovalIn: dot).fill()
        }

        let line = NSBezierPath()
        line.lineWidth = max(1.25, value * 0.5)
        line.lineCapStyle = .round
        line.move(to: NSPoint(x: 24, y: bounds.midY))
        line.line(to: NSPoint(x: bounds.width - 14, y: bounds.midY))
        strokeColor.setStroke()
        line.stroke()
    }
}

final class ColorSwatchButton: NSButton {
    var swatchColor: NSColor = .systemRed {
        didSet { needsDisplay = true }
    }

    private var isHovered = false {
        didSet {
            if oldValue != isHovered {
                needsDisplay = true
            }
        }
    }
    private var trackingAreaRef: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        bezelStyle = .regularSquare
        title = ""
        focusRingType = .none
        setButtonType(.momentaryChange)
        toolTip = "标注颜色"
        setAccessibilityLabel("标注颜色")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 42, height: 26)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func draw(_ dirtyRect: NSRect) {
        if isEnabled && (isHighlighted || isHovered) {
            let bg = NSColor(calibratedWhite: 1.0, alpha: isHighlighted ? 0.13 : 0.07)
            let pill = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5)
            bg.setFill()
            pill.fill()
        }

        // Matches Preview's stroke-color well badge: rounded gray bezel + inner stroke color square + chevron
        let wellSize: CGFloat = 18
        let wellRect = NSRect(
            x: 5,
            y: round((bounds.height - wellSize) / 2),
            width: wellSize,
            height: wellSize
        )
        let outerWell = NSBezierPath(roundedRect: wellRect, xRadius: 4.2, yRadius: 4.2)
        NSColor(calibratedWhite: 0.48, alpha: 1).setFill()
        outerWell.fill()
        NSColor(calibratedWhite: 0.62, alpha: 0.55).setStroke()
        outerWell.lineWidth = 0.6
        outerWell.stroke()

        // Inner color frame (like Preview's border color icon: colored outer square with dark center)
        let colorRect = wellRect.insetBy(dx: 2.5, dy: 2.5)
        let colorPath = NSBezierPath(roundedRect: colorRect, xRadius: 2.2, yRadius: 2.2)
        swatchColor.setFill()
        colorPath.fill()

        let innerHole = wellRect.insetBy(dx: 5.5, dy: 5.5)
        let holePath = NSBezierPath(roundedRect: innerHole, xRadius: 1.0, yRadius: 1.0)
        NSColor(calibratedWhite: 0.16, alpha: 1).setFill()
        holePath.fill()

        // Downward chevron
        let cx: CGFloat = bounds.width - 10.5
        let cy: CGFloat = bounds.midY + 0.5
        let chevron = NSBezierPath()
        chevron.move(to: NSPoint(x: cx - 3.2, y: cy - 1.6))
        chevron.line(to: NSPoint(x: cx, y: cy + 1.8))
        chevron.line(to: NSPoint(x: cx + 3.2, y: cy - 1.6))
        chevron.lineWidth = 1.4
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round
        let chevronColor = isEnabled
            ? NSColor(calibratedWhite: isHovered ? 0.85 : 0.64, alpha: 1)
            : NSColor(calibratedWhite: 0.32, alpha: 1)
        chevronColor.setStroke()
        chevron.stroke()
    }
}

final class PaletteSwatchButton: NSButton {
    let swatchColor: NSColor
    private let ring: Bool

    init(color: NSColor, ring: Bool = false) {
        self.swatchColor = color
        self.ring = ring
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        title = ""
        focusRingType = .none
        setButtonType(.momentaryChange)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: box, xRadius: 7, yRadius: 7)
        swatchColor.setFill()
        path.fill()
        NSColor(calibratedWhite: ring ? 0.72 : 0.35, alpha: ring ? 1 : 0.65).setStroke()
        path.lineWidth = ring ? 1.5 : 1
        path.stroke()
    }
}

final class ColorPaletteViewController: NSViewController {
    var onPick: ((NSColor) -> Void)?

    private let selectedColor: NSColor
    private let colors: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen, .systemTeal,
        .systemBlue, .systemPurple, .systemPink, .white, .black
    ]
    private let hexField = NSTextField()

    init(selected: NSColor) {
        self.selectedColor = selected
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: 248, height: 154)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 248, height: 154))
        root.wantsLayer = true
        view = root

        let title = NSTextField(labelWithString: "标注颜色")
        title.font = .systemFont(ofSize: 11, weight: .semibold)
        title.textColor = .secondaryLabelColor
        title.frame = NSRect(x: 12, y: 126, width: 140, height: 16)
        root.addSubview(title)

        for (index, color) in colors.enumerated() {
            let column = index % 5
            let row = index / 5
            let button = PaletteSwatchButton(color: color, ring: color == .white)
            button.tag = index
            button.target = self
            button.action = #selector(pick(_:))
            button.frame = NSRect(x: 12 + column * 45, y: 88 - row * 38, width: 30, height: 30)
            root.addSubview(button)
        }

        hexField.placeholderString = "#FF3B30"
        if let rgb = selectedColor.usingColorSpace(.sRGB) {
            hexField.stringValue = String(
                format: "#%02X%02X%02X",
                Int(round(rgb.redComponent * 255)),
                Int(round(rgb.greenComponent * 255)),
                Int(round(rgb.blueComponent * 255))
            )
        }
        hexField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        hexField.controlSize = .small
        hexField.target = self
        hexField.action = #selector(applyHex)
        hexField.frame = NSRect(x: 12, y: 22, width: 160, height: 24)
        root.addSubview(hexField)

        let apply = NSButton(title: "应用", target: self, action: #selector(applyHex))
        apply.bezelStyle = .rounded
        apply.controlSize = .small
        apply.font = .systemFont(ofSize: 11)
        apply.frame = NSRect(x: 180, y: 22, width: 56, height: 24)
        root.addSubview(apply)

        let hint = NSTextField(labelWithString: "选色或输入 HEX")
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = NSColor(calibratedWhite: 0.55, alpha: 1)
        hint.frame = NSRect(x: 12, y: 4, width: 220, height: 14)
        root.addSubview(hint)
    }

    @objc private func pick(_ sender: NSButton) {
        guard colors.indices.contains(sender.tag) else { return }
        onPick?(colors[sender.tag])
    }

    @objc private func applyHex() {
        let raw = hexField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        var value = raw
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = UInt32(value, radix: 16) else {
            NSSound.beep()
            return
        }
        let color = NSColor(
            srgbRed: CGFloat((number >> 16) & 0xFF) / 255,
            green: CGFloat((number >> 8) & 0xFF) / 255,
            blue: CGFloat(number & 0xFF) / 255,
            alpha: 1
        )
        onPick?(color)
    }
}

final class TextDragHandle: NSView {
    var onDrag: ((CGSize) -> Void)?
    var onDragStart: (() -> Void)?
    var onDragEnd: (() -> Void)?
    private var lastPoint: NSPoint?

    override var isFlipped: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        onDragStart?()
        lastPoint = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let lastPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        onDrag?(CGSize(width: point.x - lastPoint.x, height: point.y - lastPoint.y))
        self.lastPoint = point
    }

    override func mouseUp(with event: NSEvent) {
        lastPoint = nil
        onDragEnd?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let image = NSImage(systemSymbolName: "arrow.up.and.down.and.arrow.left.and.right", accessibilityDescription: "移动文字")
        let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        image?.withSymbolConfiguration(config)?.draw(in: bounds.insetBy(dx: 1, dy: 2))
    }
}

final class TextOverlayView: NSView, NSTextFieldDelegate {
    static let textInset = CGPoint(x: 7, y: 5)

    let textField = NSTextField()
    private let font: NSFont
    private let handle = TextDragHandle()
    private var suppressCommit = false
    private var isDragging = false
    private var dragLast: NSPoint?

    var onTextChanged: ((String) -> Void)?
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?
    var onMove: ((CGSize) -> Void)?

    override var isFlipped: Bool { true }

    init(text: String, font: NSFont, color: NSColor) {
        self.font = font
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.82).cgColor
        layer?.cornerRadius = 5
        layer?.borderWidth = 1.5
        layer?.borderColor = NSColor.systemBlue.cgColor

        textField.stringValue = text
        textField.placeholderString = "输入文字"
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.textColor = color
        textField.font = font
        textField.usesSingleLineMode = true
        textField.cell?.wraps = false
        textField.cell?.isScrollable = true
        textField.lineBreakMode = .byClipping
        textField.isEditable = true
        textField.delegate = self
        textField.target = self
        textField.action = #selector(commitFromField)
        addSubview(textField)

        handle.onDragStart = { [weak self] in self?.isDragging = true }
        handle.onDragEnd = { [weak self] in self?.isDragging = false }
        handle.onDrag = { [weak self] delta in
            self?.onMove?(delta)
        }
        addSubview(handle)
        updateSize()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func focus() {
        guard let window else { return }
        window.makeFirstResponder(textField)
        if let editor = textField.currentEditor() as? NSTextView {
            let length = (textField.stringValue as NSString).length
            editor.selectedRange = NSRange(location: 0, length: length)
        }
    }

    func prepareForRemoval() {
        suppressCommit = true
    }

    func setTextColor(_ color: NSColor) {
        textField.textColor = color
    }

    func updateSize() {
        let sample = textField.stringValue.isEmpty ? "输入文字" : textField.stringValue
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let textWidth = (sample as NSString).size(withAttributes: attributes).width
        let width = max(100, min(640, textWidth + 30))
        let height = max(30, font.ascender - font.descender + Self.textInset.y * 2 + 4)
        frame.size = CGSize(width: width, height: height)
        textField.frame = CGRect(
            x: Self.textInset.x,
            y: Self.textInset.y,
            width: width - Self.textInset.x * 2 - 14,
            height: height - Self.textInset.y * 2
        )
        handle.frame = CGRect(x: width - 16, y: 3, width: 12, height: 12)
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        dragLast = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragLast else { return }
        let point = convert(event.locationInWindow, from: nil)
        onMove?(CGSize(width: point.x - dragLast.x, height: point.y - dragLast.y))
        self.dragLast = point
    }

    override func mouseUp(with event: NSEvent) {
        dragLast = nil
        isDragging = false
    }

    @objc private func commitFromField() {
        onCommit?()
    }

    func controlTextDidChange(_ obj: Notification) {
        updateSize()
        onTextChanged?(textField.stringValue)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if let event = NSApp.currentEvent, event.type == .leftMouseDown,
           let canvas = superview as? EditorCanvasView,
           event.window == canvas.window {
            let point = canvas.convert(event.locationInWindow, from: nil)
            if canvas.bounds.contains(point) {
                return
            }
        }
        guard !suppressCommit, !isDragging else { return }
        onCommit?()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            onCommit?()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            onCancel?()
            return true
        }
        return false
    }
}

// MARK: - Editor sheet

final class ImageEditorViewController: NSViewController {
    private let sourceURL: URL
    private let canvas = EditorCanvasView()
    private let toolbar = NSView()
    private let hintLabel = NSTextField(labelWithString: "点文字后直接在图上输入 · 拖动标注移动 · 双击文字修改 · 选中后可改颜色/线宽")
    private let statusLabel = NSTextField(labelWithString: "")

    private lazy var textToolButton = MarkupToolbarButton(
        icon: .textBox,
        tooltip: "文字 · 点击画面直接输入，双击修改",
        target: self,
        action: #selector(selectTextTool)
    )
    private lazy var rectToolButton = MarkupToolbarButton(
        icon: .rectangle,
        tooltip: "矩形 · 拖拽绘制，点击已有标注可选中",
        target: self,
        action: #selector(selectRectangleTool)
    )
    private lazy var ellipseToolButton = MarkupToolbarButton(
        icon: .ellipse,
        tooltip: "椭圆 · 按住 Shift 画正圆",
        target: self,
        action: #selector(selectEllipseTool)
    )
    private lazy var lineToolButton = MarkupToolbarButton(
        icon: .line,
        tooltip: "直线 · 按住 Shift 45° 对齐",
        target: self,
        action: #selector(selectLineTool)
    )
    private lazy var cropToolButton = MarkupToolbarButton(
        icon: .crop,
        tooltip: "裁切 · 拖出裁切框",
        target: self,
        action: #selector(selectCropTool)
    )

    private let colorButton = ColorSwatchButton()
    private let widthButton = LineWidthPopupButton()

    private lazy var rotateLeftButton = MarkupToolbarButton(
        icon: .symbol("arrow.counterclockwise"),
        tooltip: "向左旋转 90°",
        target: self,
        action: #selector(rotateLeft)
    )
    private lazy var rotateRightButton = MarkupToolbarButton(
        icon: .symbol("arrow.clockwise"),
        tooltip: "向右旋转 90°",
        target: self,
        action: #selector(rotateRight)
    )
    private lazy var clearButton = MarkupToolbarButton(
        icon: .symbol("trash"),
        tooltip: "清除所有标注",
        target: self,
        action: #selector(clearAnnotations)
    )
    private lazy var cropButton: MarkupToolbarButton = {
        let button = MarkupToolbarButton(
            icon: .symbol("checkmark"),
            title: "应用裁切",
            tooltip: "应用当前裁切选区",
            target: self,
            action: #selector(applyCrop)
        )
        button.isAccentPill = true
        button.isHidden = true
        return button
    }()
    private lazy var copyButton = MarkupToolbarButton(
        icon: .symbol("doc.on.doc"),
        title: "复制",
        tooltip: "复制当前编辑图，可直接粘贴到聊天 App (⌘C)",
        target: self,
        action: #selector(copyEditedImage)
    )
    private lazy var closeButton = MarkupToolbarButton(
        icon: .symbol(""),
        title: "取消",
        tooltip: "关闭编辑窗口 (Esc)",
        target: self,
        action: #selector(closeEditor)
    )
    private lazy var saveButton: MarkupToolbarButton = {
        let button = MarkupToolbarButton(
            icon: .symbol(""),
            title: "保存副本…",
            tooltip: "另存为 PNG 副本",
            target: self,
            action: #selector(saveCopy)
        )
        button.isAccentPill = true
        return button
    }()

    private let spinner = NSProgressIndicator()
    private var loaded = false
    private var keyMonitor: Any?
    private var colorPopover: NSPopover?
    private var statusToken = UUID()

    var onSaved: ((URL) -> Void)?

    init(sourceURL: URL) {
        self.sourceURL = sourceURL
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: 1000, height: 700)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        removeKeyMonitor()
    }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(calibratedWhite: 0.075, alpha: 1).cgColor
        view = root

        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = NSColor(calibratedWhite: 0.14, alpha: 1).cgColor
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(toolbar)

        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor(calibratedWhite: 0.22, alpha: 1).cgColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(separator)

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(stack)

        colorButton.swatchColor = .systemRed
        colorButton.target = self
        colorButton.action = #selector(showColorPalette)
        colorButton.translatesAutoresizingMaskIntoConstraints = false
        colorButton.toolTip = "标注颜色"

        widthButton.levels = Self.lineWidthValues
        widthButton.selectedIndex = 3
        widthButton.translatesAutoresizingMaskIntoConstraints = false
        widthButton.onSelect = { [weak self] _ in self?.styleChanged() }

        clearButton.isEnabled = false
        copyButton.isEnabled = false
        saveButton.isEnabled = false
        rotateLeftButton.isEnabled = false
        rotateRightButton.isEnabled = false

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Left: Drawing & markup tools (matching macOS Preview markup bar)
        let toolsGroup = NSStackView(views: [
            rectToolButton,
            ellipseToolButton,
            lineToolButton,
            textToolButton,
            cropToolButton,
            cropButton
        ])
        toolsGroup.orientation = .horizontal
        toolsGroup.alignment = .centerY
        toolsGroup.spacing = 4
        toolsGroup.setCustomSpacing(8, after: cropToolButton)

        // Middle: Stroke width & color wells (matching Preview's style dropdowns)
        let styleGroup = NSStackView(views: [
            widthButton,
            colorButton
        ])
        styleGroup.orientation = .horizontal
        styleGroup.alignment = .centerY
        styleGroup.spacing = 4

        // Transform & clear actions
        let transformGroup = NSStackView(views: [
            rotateLeftButton,
            rotateRightButton,
            clearButton
        ])
        transformGroup.orientation = .horizontal
        transformGroup.alignment = .centerY
        transformGroup.spacing = 4

        // Right: Copy, Cancel, Save Copy
        let actionGroup = NSStackView(views: [
            copyButton,
            verticalSeparator(),
            closeButton,
            saveButton
        ])
        actionGroup.orientation = .horizontal
        actionGroup.alignment = .centerY
        actionGroup.spacing = 6

        stack.addArrangedSubview(toolsGroup)
        stack.addArrangedSubview(paddedSeparator())
        stack.addArrangedSubview(styleGroup)
        stack.addArrangedSubview(paddedSeparator())
        stack.addArrangedSubview(transformGroup)
        stack.addArrangedSubview(spacer)
        stack.addArrangedSubview(actionGroup)

        canvas.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(canvas)

        hintLabel.font = .systemFont(ofSize: 10.5)
        hintLabel.textColor = NSColor(calibratedWhite: 0.48, alpha: 1)
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(hintLabel)

        statusLabel.font = .systemFont(ofSize: 10.5)
        statusLabel.textColor = NSColor(calibratedWhite: 0.48, alpha: 1)
        statusLabel.alignment = .right
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(statusLabel)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(spinner)

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: root.topAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 40),

            separator.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),

            stack.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            canvas.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            canvas.bottomAnchor.constraint(equalTo: hintLabel.topAnchor, constant: -4),

            hintLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            hintLabel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8),
            hintLabel.heightAnchor.constraint(equalToConstant: 14),

            statusLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            statusLabel.centerYAnchor.constraint(equalTo: hintLabel.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: hintLabel.trailingAnchor, constant: 12),

            spinner.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: canvas.centerYAnchor)
        ])

        canvas.onAnnotationsChanged = { [weak self] in self?.updateState() }
        canvas.onCropChanged = { [weak self] in self?.updateState() }
        canvas.onSelectionChanged = { [weak self] in self?.updateState() }
        syncToolButtons()
        updateState()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadImage()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        installKeyMonitor()
    }

    override func viewWillDisappear() {
        removeKeyMonitor()
        super.viewWillDisappear()
    }

    private func loadImage() {
        spinner.startAnimation(nil)
        canvas.image = nil
        let url = sourceURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = ImagePipeline.shared.image(for: url, maxPixel: 8192, allowEmbedded: false)
            DispatchQueue.main.async {
                guard let self else { return }
                self.spinner.stopAnimation(nil)
                guard let image else {
                    self.showError("无法读取这张图片")
                    return
                }
                self.canvas.image = image
                self.loaded = true
                self.updateState()
            }
        }
    }

    static let lineWidthValues: [CGFloat] = [4, 7, 11, 16, 22, 30]

    private func syncToolButtons() {
        let current = canvas.tool
        textToolButton.isActiveTool = (current == .text)
        rectToolButton.isActiveTool = (current == .rectangle)
        ellipseToolButton.isActiveTool = (current == .ellipse)
        lineToolButton.isActiveTool = (current == .line)
        cropToolButton.isActiveTool = (current == .crop)
    }

    private func selectTool(_ tool: EditorTool) {
        canvas.commitActiveText()
        if tool != .crop {
            canvas.cancelCrop()
        }
        canvas.tool = tool
        syncToolButtons()
        updateState()
    }

    @objc private func selectTextTool() { selectTool(.text) }
    @objc private func selectRectangleTool() { selectTool(.rectangle) }
    @objc private func selectEllipseTool() { selectTool(.ellipse) }
    @objc private func selectLineTool() { selectTool(.line) }
    @objc private func selectCropTool() { selectTool(.crop) }

    private func updateState() {
        syncToolButtons()
        guard loaded, let image = canvas.image else {
            saveButton.isEnabled = false
            copyButton.isEnabled = false
            clearButton.isEnabled = false
            rotateLeftButton.isEnabled = false
            rotateRightButton.isEnabled = false
            cropButton.isEnabled = false
            cropButton.isHidden = true
            statusLabel.stringValue = ""
            return
        }
        saveButton.isEnabled = true
        copyButton.isEnabled = true
        rotateLeftButton.isEnabled = true
        rotateRightButton.isEnabled = true
        clearButton.isEnabled = !canvas.annotations.isEmpty
        cropButton.isEnabled = canvas.hasCrop
        cropButton.isHidden = !canvas.hasCrop
        statusLabel.stringValue = "\(image.width) × \(image.height) · \(canvas.annotations.count) 个标注"

        if let selected = canvas.selectedAnnotation {
            colorButton.swatchColor = selected.color
            let scale = max(1, CGFloat(image.width) / 1600)
            let base = selected.lineWidth / scale
            let values = Self.lineWidthValues
            let index = values.enumerated().min { abs($0.element - base) < abs($1.element - base) }?.offset ?? 3
            widthButton.selectedIndex = index
            widthButton.isEnabled = selected.text == nil
        } else {
            widthButton.isEnabled = (canvas.tool != .text && canvas.tool != .crop)
        }
    }

    @objc private func showColorPalette() {
        if let existing = colorPopover, existing.isShown {
            existing.close()
            return
        }
        let picker = ColorPaletteViewController(selected: colorButton.swatchColor)
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = picker
        picker.onPick = { [weak self, weak popover] color in
            guard let self else { return }
            self.colorButton.swatchColor = color
            let widths = Self.lineWidthValues
            let width = widths[max(0, min(self.widthButton.selectedIndex, widths.count - 1))]
            self.canvas.applyStyle(color: color, baseLineWidth: width)
            popover?.close()
            self.updateState()
        }
        colorPopover = popover
        popover.show(relativeTo: colorButton.bounds, of: colorButton, preferredEdge: .maxY)
    }

    @objc private func styleChanged() {
        let widths = Self.lineWidthValues
        let width = widths[max(0, min(widthButton.selectedIndex, widths.count - 1))]
        canvas.applyStyle(color: colorButton.swatchColor, baseLineWidth: width)
        updateState()
    }

    @objc private func rotateLeft() {
        canvas.commitActiveText()
        canvas.rotate(clockwise: false)
        updateState()
    }

    @objc private func rotateRight() {
        canvas.commitActiveText()
        canvas.rotate(clockwise: true)
        updateState()
    }

    @objc private func applyCrop() {
        canvas.commitActiveText()
        if canvas.applyCrop() {
            updateState()
        }
    }

    @objc private func clearAnnotations() {
        canvas.commitActiveText()
        canvas.clearAllAnnotations()
        updateState()
    }

    @objc private func copyEditedImage() {
        guard loaded, canvas.image != nil else {
            NSSound.beep()
            return
        }
        canvas.commitActiveText()
        if canvas.hasCrop, !canvas.applyCrop() {
            showError("请先完成裁切，再复制。")
            return
        }
        guard let output = canvas.renderedImage() else {
            showError("生成编辑图失败")
            return
        }
        let rep = NSBitmapImageRep(cgImage: output)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            showError("生成 PNG 失败")
            return
        }
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        if let tiff = rep.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            showError("无法写入剪贴板")
            return
        }
        statusToken = UUID()
        let token = statusToken
        statusLabel.stringValue = "已复制当前编辑图，可直接粘贴"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            guard let self, self.statusToken == token else { return }
            self.updateState()
        }
    }

    @objc private func saveCopy() {
        guard loaded, canvas.image != nil else { return }
        canvas.commitActiveText()
        if canvas.hasCrop {
            showError("请先点“应用裁切”，再保存。")
            return
        }
        let panel = NSSavePanel()
        panel.title = "保存编辑副本"
        panel.prompt = "保存"
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        let base = sourceURL.deletingPathExtension().lastPathComponent
        panel.nameFieldStringValue = "\(base)-编辑.png"
        panel.directoryURL = sourceURL.deletingLastPathComponent()

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            if url.standardizedFileURL == self.sourceURL.standardizedFileURL {
                self.showError("不能覆盖原图，请换一个文件名。")
                return
            }
            guard let output = self.canvas.renderedImage() else {
                self.showError("生成编辑图失败")
                return
            }
            guard let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            ) else {
                self.showError("无法写入文件")
                return
            }
            CGImageDestinationAddImage(destination, output, nil)
            guard CGImageDestinationFinalize(destination) else {
                self.showError("保存失败")
                return
            }
            self.onSaved?(url)
            self.dismiss(self)
        }

        if let window = view.window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }

    @objc private func closeEditor() {
        canvas.commitActiveText()
        dismiss(self)
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "编辑"
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func verticalSeparator() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(calibratedWhite: 0.25, alpha: 1).cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: 1).isActive = true
        view.heightAnchor.constraint(equalToConstant: 18).isActive = true
        return view
    }

    private func paddedSeparator() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let line = verticalSeparator()
        container.addSubview(line)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 15),
            container.heightAnchor.constraint(equalToConstant: 20),
            line.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            line.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window == self.view.window else { return event }
            if (event.keyCode == 36 || event.keyCode == 76),
               self.canvas.isEditingText,
               !self.canvas.textEditorHasMarkedText {
                self.canvas.commitActiveText()
                return nil
            }
            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "c" {
                self.copyEditedImage()
                return nil
            }
            if (event.keyCode == 51 || event.keyCode == 117),
               !(self.view.window?.firstResponder is NSTextView) {
                self.canvas.deleteSelected()
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}
