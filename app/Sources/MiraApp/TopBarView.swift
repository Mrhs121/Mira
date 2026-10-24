import AppKit

final class TopBarView: NSView {
    let openButton = NSButton()
    let gridButton = NSButton()
    let folderLabel = NSTextField(labelWithString: "")
    let fileLabel = NSTextField(labelWithString: "")
    let countLabel = NSTextField(labelWithString: "")
    let editButton = NSButton()
    let fitButton = NSButton()
    let infoButton = NSButton()
    let shareButton = NSButton()

    var onOpen: (() -> Void)?
    var onGrid: (() -> Void)?
    var onEdit: (() -> Void)?
    var onFit: (() -> Void)?
    var onInfo: (() -> Void)?
    var onShare: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var mouseDownCanMoveWindow: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if hit is NSButton {
            return hit
        }
        let local = superview.map { convert(point, from: $0) } ?? point
        return bounds.contains(local) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.performZoom(nil)
        } else {
            window?.performDrag(with: event)
        }
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 1).cgColor

        openButton.title = "打开"
        openButton.image = symbol("folder")
        openButton.imagePosition = .imageLeading
        openButton.imageScaling = .scaleProportionallyDown
        openButton.font = .systemFont(ofSize: 12, weight: .medium)
        openButton.isBordered = false
        openButton.contentTintColor = NSColor(calibratedWhite: 0.86, alpha: 1)
        openButton.target = self
        openButton.action = #selector(openClicked)

        configureSymbolButton(gridButton, name: "square.grid.2x2", tooltip: "网格 (G)", action: #selector(gridClicked))
        configureSymbolButton(editButton, name: "pencil.tip", tooltip: "编辑 (⌘E)", action: #selector(editClicked))
        configureSymbolButton(infoButton, name: "sidebar.right", tooltip: "信息 (I)", action: #selector(infoClicked))
        configureSymbolButton(shareButton, name: "square.and.arrow.up", tooltip: "分享", action: #selector(shareClicked))

        fitButton.title = "适应"
        fitButton.font = .systemFont(ofSize: 12, weight: .medium)
        fitButton.isBordered = false
        fitButton.contentTintColor = NSColor(calibratedWhite: 0.82, alpha: 1)
        fitButton.target = self
        fitButton.action = #selector(fitClicked)

        folderLabel.font = .systemFont(ofSize: 12, weight: .medium)
        folderLabel.textColor = NSColor(calibratedWhite: 0.74, alpha: 1)
        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        fileLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        fileLabel.textColor = NSColor(calibratedWhite: 0.95, alpha: 1)
        fileLabel.alignment = .center
        fileLabel.lineBreakMode = .byTruncatingMiddle

        countLabel.font = .systemFont(ofSize: 10.5, weight: .regular)
        countLabel.textColor = NSColor(calibratedWhite: 0.56, alpha: 1)
        countLabel.alignment = .center

        let left = NSStackView(views: [openButton, gridButton, folderLabel])
        left.orientation = .horizontal
        left.alignment = .centerY
        left.spacing = 6
        left.setHuggingPriority(.defaultHigh, for: .horizontal)

        let center = NSStackView(views: [fileLabel, countLabel])
        center.orientation = .horizontal
        center.alignment = .firstBaseline
        center.spacing = 8
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let right = NSStackView(views: [editButton, fitButton, infoButton, shareButton])
        right.orientation = .horizontal
        right.alignment = .centerY
        right.spacing = 8

        [left, center, right].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor(calibratedWhite: 0.2, alpha: 1).cgColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        NSLayoutConstraint.activate([
            left.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 82),
            left.centerYAnchor.constraint(equalTo: centerYAnchor),
            left.trailingAnchor.constraint(lessThanOrEqualTo: center.leadingAnchor, constant: -12),

            center.centerXAnchor.constraint(equalTo: centerXAnchor),
            center.centerYAnchor.constraint(equalTo: centerYAnchor),
            center.widthAnchor.constraint(lessThanOrEqualToConstant: 360),

            right.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            right.centerYAnchor.constraint(equalTo: centerYAnchor),
            right.leadingAnchor.constraint(greaterThanOrEqualTo: center.trailingAnchor, constant: 12),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),

            heightAnchor.constraint(equalToConstant: 32)
        ])

        gridButton.toolTip = "网格 (G)"
        editButton.toolTip = "编辑 (⌘E)"
        infoButton.toolTip = "信息 (I)"
        shareButton.toolTip = "分享"
        openButton.toolTip = "打开文件或文件夹 (⌘O)"
    }

    private func configureSymbolButton(_ button: NSButton, name: String, tooltip: String, action: Selector) {
        button.image = symbol(name)
        button.imageScaling = .scaleProportionallyDown
        button.isBordered = false
        button.contentTintColor = NSColor(calibratedWhite: 0.76, alpha: 1)
        button.target = self
        button.action = action
        button.toolTip = tooltip
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 26).isActive = true
        button.heightAnchor.constraint(equalToConstant: 26).isActive = true
    }

    private func symbol(_ name: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    }

    func update(folderName: String, fileName: String, index: Int, total: Int) {
        folderLabel.stringValue = folderName
        fileLabel.stringValue = fileName
        countLabel.stringValue = total > 0 ? "第 \(index + 1) 张，共 \(total) 张" : ""
    }

    func setGridActive(_ active: Bool) {
        gridButton.contentTintColor = active
            ? NSColor(calibratedRed: 0.42, green: 0.72, blue: 1, alpha: 1)
            : NSColor(calibratedWhite: 0.76, alpha: 1)
    }

    func setInspectorActive(_ active: Bool) {
        infoButton.contentTintColor = active
            ? NSColor(calibratedRed: 0.42, green: 0.72, blue: 1, alpha: 1)
            : NSColor(calibratedWhite: 0.76, alpha: 1)
    }

    func setFitTitle(_ title: String) {
        fitButton.title = title
    }

    @objc private func openClicked() { onOpen?() }
    @objc private func gridClicked() { onGrid?() }
    @objc private func editClicked() { onEdit?() }
    @objc private func fitClicked() { onFit?() }
    @objc private func infoClicked() { onInfo?() }
    @objc private func shareClicked() { onShare?() }
}
