import AppKit
import MiraCore

final class GridCollectionView: NSCollectionView {
    var onDoubleClick: ((IndexPath) -> Void)?
    var onContextMenu: ((IndexPath) -> NSMenu?)?

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            let point = convert(event.locationInWindow, from: nil)
            if let indexPath = indexPathForItem(at: point) {
                super.mouseDown(with: event)
                onDoubleClick?(indexPath)
                return
            }
        }
        super.mouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard let indexPath = indexPathForItem(at: point) else {
            return super.menu(for: event)
        }
        return onContextMenu?(indexPath) ?? super.menu(for: event)
    }
}

final class GridViewController: NSViewController, NSCollectionViewDataSource, NSCollectionViewDelegate {
    private(set) var items: [ImageItem] = []
    private var collectionView: GridCollectionView!
    private var scrollView: NSScrollView!
    private var suppressSelectionCallback = false

    var onSelect: ((Int) -> Void)?
    var onOpen: ((Int) -> Void)?
    var onContextMenu: ((Int) -> NSMenu?)?

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(calibratedWhite: 0.075, alpha: 1).cgColor

        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 196, height: 174)
        layout.minimumInteritemSpacing = 14
        layout.minimumLineSpacing = 16
        layout.sectionInset = NSEdgeInsets(top: 20, left: 22, bottom: 20, right: 22)

        collectionView = GridCollectionView()
        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.backgroundColors = [.clear]
        collectionView.register(GridItem.self, forItemWithIdentifier: GridItem.identifier)
        collectionView.onDoubleClick = { [weak self] indexPath in
            self?.onOpen?(indexPath.item)
        }
        collectionView.onContextMenu = { [weak self] indexPath in
            self?.onContextMenu?(indexPath.item)
        }

        scrollView = NSScrollView()
        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        view = root
    }

    func reload(items: [ImageItem], selectedIndex: Int?) {
        self.items = items
        guard isViewLoaded else { return }
        collectionView.reloadData()
        if let selectedIndex, items.indices.contains(selectedIndex) {
            select(index: selectedIndex, scroll: true)
        }
    }

    func select(index: Int, scroll: Bool) {
        guard isViewLoaded, items.indices.contains(index) else { return }
        suppressSelectionCallback = true
        let oldSelection = collectionView.selectionIndexPaths
        if !oldSelection.isEmpty {
            collectionView.deselectItems(at: oldSelection)
        }
        let indexPath = IndexPath(item: index, section: 0)
        collectionView.selectItems(at: [indexPath], scrollPosition: scroll ? .nearestVerticalEdge : [])
        suppressSelectionCallback = false
        miraLog("grid selection -> \(collectionView.selectionIndexPaths.map(\.item))")
    }

    func focus() {
        guard isViewLoaded else { return }
        view.window?.makeFirstResponder(collectionView)
    }

    func selectedIndex() -> Int? {
        guard isViewLoaded else { return nil }
        return collectionView.selectionIndexPaths.first?.item
    }

    func moveSelection(by delta: Int) {
        guard isViewLoaded, !items.isEmpty else { return }
        let current = selectedIndex() ?? 0
        let next = min(max(current + delta, 0), items.count - 1)
        if next != current {
            select(index: next, scroll: true)
            onSelect?(next)
        }
    }

    func openSelection() {
        guard let index = selectedIndex() else { return }
        onOpen?(index)
    }

    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        1
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: GridItem.identifier, for: indexPath)
        guard let gridItem = item as? GridItem, items.indices.contains(indexPath.item) else {
            return item
        }
        gridItem.configure(with: items[indexPath.item])
        gridItem.onContextMenu = { [weak self] in
            self?.onContextMenu?(indexPath.item)
        }
        return gridItem
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard !suppressSelectionCallback, let index = indexPaths.first?.item else { return }
        onSelect?(index)
    }
}

final class GridItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("GridItem")

    private let thumbView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private var representedURL: URL?
    var onContextMenu: (() -> NSMenu?)?

    override func loadView() {
        let card = ContextMenuHostView()
        card.onContextMenu = { [weak self] in self?.onContextMenu?() }
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1).cgColor
        card.layer?.cornerRadius = 9
        card.layer?.borderColor = NSColor(calibratedWhite: 0.18, alpha: 1).cgColor
        card.layer?.borderWidth = 1

        thumbView.imageScaling = .scaleProportionallyUpOrDown
        thumbView.translatesAutoresizingMaskIntoConstraints = false
        thumbView.wantsLayer = true
        thumbView.layer?.cornerRadius = 7
        thumbView.layer?.masksToBounds = true
        card.addSubview(thumbView)

        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = NSColor(calibratedWhite: 0.88, alpha: 1)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(titleLabel)

        subtitleLabel.font = .systemFont(ofSize: 10)
        subtitleLabel.textColor = NSColor(calibratedWhite: 0.48, alpha: 1)
        subtitleLabel.lineBreakMode = .byTruncatingMiddle
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            thumbView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            thumbView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
            thumbView.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            thumbView.heightAnchor.constraint(equalToConstant: 126),

            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            titleLabel.topAnchor.constraint(equalTo: thumbView.bottomAnchor, constant: 7),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2)
        ])

        view = card
    }

    override var isSelected: Bool {
        didSet {
            view.layer?.borderColor = isSelected
                ? NSColor(calibratedRed: 0.42, green: 0.72, blue: 1, alpha: 1).cgColor
                : NSColor(calibratedWhite: 0.18, alpha: 1).cgColor
            view.layer?.borderWidth = isSelected ? 2 : 1
        }
    }

    func configure(with item: ImageItem) {
        representedURL = item.url
        titleLabel.stringValue = item.fileName
        subtitleLabel.stringValue = ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file)
        thumbView.image = nil

        let url = item.url
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = ImagePipeline.shared.image(for: url, maxPixel: 420, allowEmbedded: true)
            let nsImage = image.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
            DispatchQueue.main.async {
                guard let self, self.representedURL == url else { return }
                self.thumbView.image = nsImage
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedURL = nil
        thumbView.image = nil
        titleLabel.stringValue = ""
        subtitleLabel.stringValue = ""
    }
}
