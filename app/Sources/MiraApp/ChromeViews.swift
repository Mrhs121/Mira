import AppKit
import MiraCore

final class BrowserRootView: NSView {
    var onDropURLs: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [URL], !urls.isEmpty else {
            return false
        }
        onDropURLs?(urls)
        return true
    }
}

final class EmptyStateView: NSView {
    var onOpen: (() -> Void)?

    private let button = NSButton(title: "打开文件夹…", target: nil, action: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var mouseDownCanMoveWindow: Bool { false }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.075, alpha: 1).cgColor

        let icon = NSImageView()
        icon.image = NSImage(
            systemSymbolName: "photo.on.rectangle.angled",
            accessibilityDescription: "图片"
        )?.withSymbolConfiguration(.init(pointSize: 44, weight: .light))
        icon.contentTintColor = NSColor(calibratedWhite: 0.36, alpha: 1)
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)

        let title = NSTextField(labelWithString: "打开一个文件夹")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        title.textColor = NSColor(calibratedWhite: 0.9, alpha: 1)
        title.translatesAutoresizingMaskIntoConstraints = false
        addSubview(title)

        let subtitle = NSTextField(wrappingLabelWithString: "按方向键连续看，双击放大。\n也可以把文件夹直接拖进来。")
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = NSColor(calibratedWhite: 0.5, alpha: 1)
        subtitle.alignment = .center
        subtitle.maximumNumberOfLines = 2
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitle)

        button.bezelStyle = .rounded
        button.controlSize = .large
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.target = self
        button.action = #selector(openClicked)
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)

        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -92),

            title.centerXAnchor.constraint(equalTo: centerXAnchor),
            title.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 18),

            subtitle.centerXAnchor.constraint(equalTo: centerXAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),

            button.centerXAnchor.constraint(equalTo: centerXAnchor),
            button.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 22)
        ])
    }

    @objc private func openClicked() {
        onOpen?()
    }
}

final class ToastView: NSView {
    private let label = NSTextField(labelWithString: "")
    private var hideWorkItem: DispatchWorkItem?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.18, alpha: 0.96).cgColor
        layer?.cornerRadius = 8
        layer?.borderColor = NSColor(calibratedWhite: 0.28, alpha: 0.7).cgColor
        layer?.borderWidth = 1
        alphaValue = 0
        isHidden = true

        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = NSColor(calibratedWhite: 0.92, alpha: 1)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var mouseDownCanMoveWindow: Bool { false }

    func show(_ message: String, duration: TimeInterval = 3.5) {
        hideWorkItem?.cancel()
        label.stringValue = message
        isHidden = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            animator().alphaValue = 1
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                self.animator().alphaValue = 0
            } completionHandler: {
                self.isHidden = true
            }
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}

/// A plain container that can provide a dynamic context menu.
final class ContextMenuHostView: NSView {
    var onContextMenu: (() -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        onContextMenu?() ?? super.menu(for: event)
    }
}
