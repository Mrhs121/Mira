import AppKit
import MiraCore

final class FilmstripCollectionView: NSCollectionView {
    var onContextMenu: ((IndexPath) -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard let indexPath = indexPathForItem(at: point) else {
            return super.menu(for: event)
        }
        return onContextMenu?(indexPath) ?? super.menu(for: event)
    }
}

final class FilmstripView: NSView, NSCollectionViewDataSource, NSCollectionViewDelegate {
    private var items: [ImageItem] = []
    private var collectionView: FilmstripCollectionView!
    private var suppressCallback = false

    var onSelect: ((Int) -> Void)?
    var onContextMenu: ((Int) -> NSMenu?)?

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
        layer?.backgroundColor = NSColor(calibratedWhite: 0.095, alpha: 1).cgColor

        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor(calibratedWhite: 0.19, alpha: 1).cgColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        let layout = NSCollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = NSSize(width: 64, height: 48)
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.sectionInset = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)

        collectionView = FilmstripCollectionView()
        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.backgroundColors = [.clear]
        collectionView.register(FilmstripItem.self, forItemWithIdentifier: FilmstripItem.identifier)
        collectionView.onContextMenu = { [weak self] indexPath in
            self?.onContextMenu?(indexPath.item)
        }

        let scrollView = NSScrollView()
        scrollView.documentView = collectionView
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),

            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    func reload(items: [ImageItem], selectedIndex: Int?) {
        self.items = items
        collectionView.reloadData()
        if let selectedIndex, items.indices.contains(selectedIndex) {
            select(index: selectedIndex, scroll: true)
        }
    }

    func select(index: Int, scroll: Bool) {
        guard items.indices.contains(index) else { return }
        suppressCallback = true
        let oldSelection = collectionView.selectionIndexPaths
        if !oldSelection.isEmpty {
            collectionView.deselectItems(at: oldSelection)
        }
        collectionView.selectItems(
            at: [IndexPath(item: index, section: 0)],
            scrollPosition: scroll ? .nearestHorizontalEdge : []
        )
        suppressCallback = false
        miraLog("filmstrip selection -> \(collectionView.selectionIndexPaths.map(\.item))")
    }

    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: FilmstripItem.identifier, for: indexPath)
        guard let filmItem = item as? FilmstripItem, items.indices.contains(indexPath.item) else {
            return item
        }
        filmItem.configure(with: items[indexPath.item])
        filmItem.onContextMenu = { [weak self] in
            self?.onContextMenu?(indexPath.item)
        }
        return filmItem
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard !suppressCallback, let index = indexPaths.first?.item else { return }
        onSelect?(index)
    }
}

final class FilmstripItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("FilmstripItem")
    private let thumbView = NSImageView()
    private var representedURL: URL?
    var onContextMenu: (() -> NSMenu?)?

    override func loadView() {
        let container = ContextMenuHostView()
        container.onContextMenu = { [weak self] in self?.onContextMenu?() }
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1).cgColor
        container.layer?.cornerRadius = 5
        container.layer?.borderColor = NSColor.clear.cgColor
        container.layer?.borderWidth = 2

        thumbView.imageScaling = .scaleProportionallyUpOrDown
        thumbView.translatesAutoresizingMaskIntoConstraints = false
        thumbView.wantsLayer = true
        thumbView.layer?.cornerRadius = 3
        thumbView.layer?.masksToBounds = true
        container.addSubview(thumbView)

        NSLayoutConstraint.activate([
            thumbView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
            thumbView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -2),
            thumbView.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
            thumbView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2)
        ])

        view = container
    }

    override var isSelected: Bool {
        didSet {
            view.layer?.borderColor = isSelected
                ? NSColor(calibratedRed: 0.42, green: 0.72, blue: 1, alpha: 1).cgColor
                : NSColor.clear.cgColor
        }
    }

    func configure(with item: ImageItem) {
        representedURL = item.url
        thumbView.image = nil
        let url = item.url
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = ImagePipeline.shared.image(for: url, maxPixel: 160, allowEmbedded: true)
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
    }
}
