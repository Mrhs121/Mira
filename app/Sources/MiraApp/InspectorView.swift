import AppKit
import MiraCore

private final class FlippedContentView: NSView {
    override var isFlipped: Bool { true }
}

final class InspectorView: NSView {
    private let header = NSTextField(labelWithString: "信息")
    private let scrollView = NSScrollView()
    private let contentView = FlippedContentView()
    private let stack = NSStackView()

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
        layer?.backgroundColor = NSColor(calibratedWhite: 0.105, alpha: 1).cgColor

        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor(calibratedWhite: 0.2, alpha: 1).cgColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        header.font = .systemFont(ofSize: 12, weight: .semibold)
        header.textColor = NSColor(calibratedWhite: 0.92, alpha: 1)
        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = contentView

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.widthAnchor.constraint(equalToConstant: 1),

            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            header.topAnchor.constraint(equalTo: topAnchor, constant: 16),

            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),

            contentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 0),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18)
        ])
    }

    func update(item: ImageItem?, metadata: ImageMetadata?) {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        guard let item else {
            addEmpty()
            return
        }

        addSection("文件")
        addRow("名称", item.fileName)
        addRow("大小", ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))
        addRow("修改", Self.dateFormatter.string(from: item.modificationDate))

        addSection("图像")
        if let metadata, metadata.pixelWidth > 0 {
            addRow("尺寸", "\(metadata.pixelWidth) × \(metadata.pixelHeight)")
            addRow("像素", String(format: "%.1f MP", metadata.megapixels))
            addRow("色彩", metadata.colorModel ?? "—")
            if let dpi = metadata.dpiWidth, dpi > 0 {
                addRow("分辨率", String(format: "%.0f dpi", dpi))
            }
        } else {
            addRow("尺寸", "读取中…")
        }

        if let metadata, hasCaptureInfo(metadata) {
            addSection("拍摄")
            if let make = metadata.cameraMake, !make.isEmpty {
                addRow("相机", [make, metadata.cameraModel].compactMap { $0 }.joined(separator: " "))
            } else if let model = metadata.cameraModel {
                addRow("相机", model)
            }
            if let lens = metadata.lens, !lens.isEmpty {
                addRow("镜头", lens)
            }
            if let exposure = metadata.exposureTime, exposure > 0 {
                addRow("快门", exposure >= 1 ? String(format: "%.1fs", exposure) : "1/\(Int(round(1 / exposure)))s")
            }
            if let fNumber = metadata.fNumber, fNumber > 0 {
                addRow("光圈", String(format: "f/%.1f", fNumber))
            }
            if let iso = metadata.iso {
                addRow("ISO", "\(iso)")
            }
            if let focal = metadata.focalLength, focal > 0 {
                addRow("焦距", String(format: "%.0f mm", focal))
            }
            if let date = metadata.dateTaken, !date.isEmpty {
                addRow("拍摄时间", date)
            }
        }

        addSection("")
        let hint = NSTextField(wrappingLabelWithString: "⌘C 复制图片   ⇧⌘R 在 Finder 中显示")
        hint.font = .systemFont(ofSize: 10.5)
        hint.textColor = NSColor(calibratedWhite: 0.46, alpha: 1)
        hint.maximumNumberOfLines = 2
        stack.addArrangedSubview(hint)
        hint.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func addEmpty() {
        let label = NSTextField(wrappingLabelWithString: "打开一张图片\n查看文件与拍摄信息")
        label.font = .systemFont(ofSize: 12)
        label.textColor = NSColor(calibratedWhite: 0.45, alpha: 1)
        stack.addArrangedSubview(label)
    }

    private func addSection(_ title: String) {
        let spacer = NSView()
        spacer.heightAnchor.constraint(equalToConstant: title.isEmpty ? 12 : 16).isActive = true
        stack.addArrangedSubview(spacer)

        guard !title.isEmpty else { return }
        let label = NSTextField(labelWithString: title.uppercased())
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = NSColor(calibratedWhite: 0.42, alpha: 1)
        stack.addArrangedSubview(label)
        let gap = NSView()
        gap.heightAnchor.constraint(equalToConstant: 7).isActive = true
        stack.addArrangedSubview(gap)
    }

    private func addRow(_ name: String, _ value: String) {
        let nameLabel = NSTextField(labelWithString: name)
        nameLabel.font = .systemFont(ofSize: 11)
        nameLabel.textColor = NSColor(calibratedWhite: 0.47, alpha: 1)
        nameLabel.widthAnchor.constraint(equalToConstant: 54).isActive = true

        let valueLabel = NSTextField(wrappingLabelWithString: value)
        valueLabel.font = .systemFont(ofSize: 11)
        valueLabel.textColor = NSColor(calibratedWhite: 0.82, alpha: 1)
        valueLabel.isSelectable = true
        valueLabel.maximumNumberOfLines = 2
        valueLabel.lineBreakMode = .byTruncatingMiddle

        let row = NSStackView(views: [nameLabel, valueLabel])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let gap = NSView()
        gap.heightAnchor.constraint(equalToConstant: 5).isActive = true
        stack.addArrangedSubview(gap)
    }

    private func hasCaptureInfo(_ metadata: ImageMetadata) -> Bool {
        metadata.cameraMake != nil
            || metadata.cameraModel != nil
            || metadata.lens != nil
            || metadata.exposureTime != nil
            || metadata.fNumber != nil
            || metadata.iso != nil
            || metadata.focalLength != nil
            || metadata.dateTaken != nil
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
