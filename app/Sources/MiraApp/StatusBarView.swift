import AppKit
import MiraCore

final class StatusBarView: NSView {
    private let leftLabel = NSTextField(labelWithString: "")
    private let centerLabel = NSTextField(labelWithString: "")
    private let rightLabel = NSTextField(labelWithString: "")

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
        layer?.backgroundColor = NSColor(calibratedWhite: 0.085, alpha: 1).cgColor

        [leftLabel, centerLabel, rightLabel].forEach {
            $0.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
            $0.textColor = NSColor(calibratedWhite: 0.52, alpha: 1)
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        centerLabel.alignment = .center
        rightLabel.alignment = .right

        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor(calibratedWhite: 0.18, alpha: 1).cgColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        NSLayoutConstraint.activate([
            leftLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            leftLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            centerLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            centerLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            rightLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            rightLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            leftLabel.trailingAnchor.constraint(lessThanOrEqualTo: centerLabel.leadingAnchor, constant: -12),
            centerLabel.trailingAnchor.constraint(lessThanOrEqualTo: rightLabel.leadingAnchor, constant: -12),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
            heightAnchor.constraint(equalToConstant: 29)
        ])
    }

    func update(index: Int, total: Int, item: ImageItem?, zoomText: String, dimensions: CGSize?) {
        if total > 0 {
            leftLabel.stringValue = "\(index + 1) / \(total)"
        } else {
            leftLabel.stringValue = ""
        }

        if let item {
            centerLabel.stringValue = item.fileName
        } else {
            centerLabel.stringValue = ""
        }

        var parts: [String] = []
        if let dimensions, dimensions.width > 0, dimensions.height > 0 {
            parts.append("\(Int(dimensions.width)) × \(Int(dimensions.height))")
        }
        if let item {
            parts.append(ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))
        }
        if total > 0, !zoomText.isEmpty {
            parts.append(zoomText)
        }
        rightLabel.stringValue = parts.joined(separator: "   ")
    }
}
