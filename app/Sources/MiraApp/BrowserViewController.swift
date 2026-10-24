import AppKit
import UniformTypeIdentifiers
import MiraCore

final class BrowserViewController: NSViewController {
    enum DisplayMode {
        case view
        case grid
    }

    private let pipeline = ImagePipeline.shared

    private(set) var items: [ImageItem] = []
    private(set) var currentIndex = 0
    private(set) var folderURL: URL?
    private var mode: DisplayMode = .view
    private var inspectorVisible = true
    private var inspectorWasVisible = true
    private var sort: ImageSort = .name
    private var ascending = true

    private var loadToken = UUID()
    private var scanToken = UUID()
    private var keyMonitor: Any?
    private var slideshowTimer: Timer?
    private var deletedItems: [(original: URL, trash: URL)] = []

    private let topBar = TopBarView()
    private let contentArea = NSView()
    private let canvas = ImageCanvasView()
    private let inspector = InspectorView()
    private let filmstrip = FilmstripView()
    private let statusBar = StatusBarView()
    private let gridVC = GridViewController()
    private let gridContainer = NSView()
    private let emptyState = EmptyStateView()
    private let toast = ToastView()

    private var inspectorWidth: NSLayoutConstraint!
    private var filmstripHeight: NSLayoutConstraint!

    override func loadView() {
        let root = BrowserRootView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(calibratedWhite: 0.075, alpha: 1).cgColor
        root.onDropURLs = { [weak self] urls in
            self?.open(urls: urls)
        }
        view = root

        contentArea.wantsLayer = true
        contentArea.layer?.backgroundColor = NSColor(calibratedWhite: 0.075, alpha: 1).cgColor
        contentArea.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(contentArea)

        topBar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(topBar)

        filmstrip.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(filmstrip)

        statusBar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(statusBar)

        canvas.translatesAutoresizingMaskIntoConstraints = false
        contentArea.addSubview(canvas)

        inspector.translatesAutoresizingMaskIntoConstraints = false
        contentArea.addSubview(inspector)

        addChild(gridVC)
        gridContainer.translatesAutoresizingMaskIntoConstraints = false
        gridContainer.isHidden = true
        contentArea.addSubview(gridContainer)
        gridVC.view.translatesAutoresizingMaskIntoConstraints = false
        gridContainer.addSubview(gridVC.view)

        emptyState.translatesAutoresizingMaskIntoConstraints = false
        emptyState.isHidden = true
        contentArea.addSubview(emptyState)

        toast.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(toast)

        inspectorWidth = inspector.widthAnchor.constraint(equalToConstant: 300)
        filmstripHeight = filmstrip.heightAnchor.constraint(equalToConstant: 92)

        NSLayoutConstraint.activate([
            topBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            topBar.topAnchor.constraint(equalTo: root.topAnchor),

            contentArea.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            contentArea.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            contentArea.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            contentArea.bottomAnchor.constraint(equalTo: filmstrip.topAnchor),

            filmstrip.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            filmstrip.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            filmstrip.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            filmstripHeight,

            statusBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            canvas.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            canvas.topAnchor.constraint(equalTo: contentArea.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
            canvas.trailingAnchor.constraint(equalTo: inspector.leadingAnchor),

            inspector.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            inspector.topAnchor.constraint(equalTo: contentArea.topAnchor),
            inspector.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
            inspectorWidth,

            gridContainer.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            gridContainer.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            gridContainer.topAnchor.constraint(equalTo: contentArea.topAnchor),
            gridContainer.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),

            gridVC.view.leadingAnchor.constraint(equalTo: gridContainer.leadingAnchor),
            gridVC.view.trailingAnchor.constraint(equalTo: gridContainer.trailingAnchor),
            gridVC.view.topAnchor.constraint(equalTo: gridContainer.topAnchor),
            gridVC.view.bottomAnchor.constraint(equalTo: gridContainer.bottomAnchor),

            emptyState.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            emptyState.topAnchor.constraint(equalTo: contentArea.topAnchor),
            emptyState.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),

            toast.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: statusBar.topAnchor, constant: -14),
            toast.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 80),
            toast.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -20)
        ])

        wireActions()
        emptyState.onOpen = { [weak self] in self?.openDocument(nil) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        gridVC.onSelect = { [weak self] index in
            self?.select(index: index, show: false)
        }
        gridVC.onOpen = { [weak self] index in
            guard let self else { return }
            self.select(index: index, show: false)
            self.setMode(.view)
        }
        filmstrip.onSelect = { [weak self] index in
            self?.select(index: index, show: true)
        }
        canvas.onZoomChanged = { [weak self] _ in
            self?.updateStatus()
        }
        canvas.onNeedsDetail = { [weak self] in
            self?.loadDetail()
        }
        if items.isEmpty {
            showEmpty()
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        installKeyMonitor()
        if mode == .grid {
            gridVC.focus()
        } else {
            view.window?.makeFirstResponder(canvas)
        }
    }

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        slideshowTimer?.invalidate()
    }

    private func wireActions() {
        topBar.onOpen = { [weak self] in self?.openDocument(nil) }
        topBar.onGrid = { [weak self] in self?.toggleGrid(nil) }
        topBar.onEdit = { [weak self] in self?.editImage(nil) }
        topBar.onFit = { [weak self] in self?.fitImage(nil) }
        topBar.onInfo = { [weak self] in self?.toggleInspector(nil) }
        topBar.onShare = { [weak self] in self?.share(nil) }

        canvas.onContextMenu = { [weak self] in self?.makeImageContextMenu() }
        gridVC.onContextMenu = { [weak self] index in
            guard let self else { return nil }
            self.select(index: index, show: false)
            return self.makeImageContextMenu()
        }
        filmstrip.onContextMenu = { [weak self] index in
            guard let self else { return nil }
            self.select(index: index, show: true)
            return self.makeImageContextMenu()
        }
    }

    // MARK: - Context menu

    private func makeImageContextMenu() -> NSMenu? {
        guard items.indices.contains(currentIndex) else { return nil }
        let item = items[currentIndex]
        miraLog("context menu requested for \(item.fileName)")
        let menu = NSMenu()
        menu.autoenablesItems = false

        let header = NSMenuItem(title: item.fileName, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        if mode == .grid {
            menu.addItem(contextMenuItem("查看大图", symbol: "eye", action: #selector(viewCurrent(_:))))
        }
        menu.addItem(contextMenuItem("编辑…", symbol: "pencil.tip", action: #selector(editImage(_:))))
        menu.addItem(contextMenuItem("在 Finder 中显示", symbol: "folder", action: #selector(revealInFinder(_:))))
        menu.addItem(.separator())

        if mode == .view {
            let copyImageItem = contextMenuItem("复制图片", symbol: "doc.on.doc", action: #selector(copyImage(_:)))
            copyImageItem.isEnabled = canvas.image != nil
            menu.addItem(copyImageItem)
        }
        menu.addItem(contextMenuItem("复制文件", symbol: "doc", action: #selector(copyFile(_:))))
        menu.addItem(contextMenuItem("复制文件路径", symbol: "link", action: #selector(copyPath(_:))))
        menu.addItem(contextMenuItem("分享…", symbol: "square.and.arrow.up", action: #selector(share(_:))))
        menu.addItem(.separator())

        menu.addItem(contextMenuItem("重命名…", symbol: "pencil", action: #selector(renameCurrent(_:))))
        menu.addItem(contextMenuItem("移到废纸篓", symbol: "trash", action: #selector(deleteCurrent(_:)), destructive: true))

        if mode == .view {
            menu.addItem(.separator())
            menu.addItem(contextMenuItem("适应窗口", symbol: "arrow.up.left.and.arrow.down.right", action: #selector(fitImage(_:))))
            menu.addItem(contextMenuItem("100%", symbol: "1.magnifyingglass", action: #selector(actualSize(_:))))
            menu.addItem(contextMenuItem("信息面板", symbol: "sidebar.right", action: #selector(toggleInspector(_:))))
        }

        return menu
    }

    private func contextMenuItem(_ title: String, symbol: String, action: Selector, destructive: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
        if destructive {
            item.attributedTitle = NSAttributedString(
                string: title,
                attributes: [.foregroundColor: NSColor.systemRed]
            )
        }
        return item
    }

    // MARK: - Opening

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = "打开图片或文件夹"
        panel.message = "选择一个文件夹，或直接选择一张图片。"
        panel.prompt = "打开"
        panel.allowedContentTypes = [.image, .folder]
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true

        let handle: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.open(urls: [url])
        }

        if let window = view.window {
            panel.beginSheetModal(for: window, completionHandler: handle)
        } else {
            handle(panel.runModal())
        }
    }

    func open(urls: [URL]) {
        guard let url = urls.first else { return }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            openFolder(url, selectFile: nil)
        } else {
            openFile(url)
        }
    }

    func openFile(_ url: URL) {
        openFolder(url.deletingLastPathComponent(), selectFile: url)
    }

    func openFolder(_ url: URL, selectFile: URL?) {
        folderURL = url
        mode = .view
        topBar.setGridActive(false)
        topBar.update(folderName: url.lastPathComponent, fileName: "读取中…", index: 0, total: 0)
        statusBar.update(index: 0, total: 0, item: nil, zoomText: "", dimensions: nil)
        view.window?.title = "Mira — \(url.lastPathComponent)"
        emptyState.isHidden = true
        canvas.showPlaceholder(pixelSize: nil)
        filmstrip.isHidden = true
        filmstripHeight.constant = 0
        inspector.isHidden = true
        inspectorWidth.constant = 0
        gridContainer.isHidden = true

        let token = UUID()
        scanToken = token
        let sort = self.sort
        let ascending = self.ascending
        let scanStarted = CFAbsoluteTimeGetCurrent()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try FolderScanner.scan(folder: url, sort: sort, ascending: ascending) }
            if case .success(let scanned) = result {
                miraLog(String(format: "scan %@: %d images in %.1fms", url.lastPathComponent, scanned.count, (CFAbsoluteTimeGetCurrent() - scanStarted) * 1000))
            }
            DispatchQueue.main.async {
                guard let self, self.scanToken == token else { return }
                switch result {
                case .success(let items):
                    self.applyScan(items: items, folder: url, selectFile: selectFile)
                case .failure(let error):
                    self.showError("无法读取文件夹", error)
                    self.showEmpty()
                }
            }
        }
    }

    private func applyScan(items: [ImageItem], folder: URL, selectFile: URL?) {
        self.items = items
        self.folderURL = folder
        guard !items.isEmpty else {
            showEmpty()
            return
        }

        let target = selectFile?.standardizedFileURL
        currentIndex = target.flatMap { target in
            items.firstIndex { $0.url.standardizedFileURL == target }
        } ?? 0
        currentIndex = min(currentIndex, items.count - 1)

        emptyState.isHidden = true
        filmstrip.isHidden = false
        filmstripHeight.constant = 92
        inspector.isHidden = !inspectorVisible
        inspectorWidth.constant = inspectorVisible ? 300 : 0
        gridContainer.isHidden = true

        filmstrip.reload(items: items, selectedIndex: currentIndex)
        gridVC.reload(items: items, selectedIndex: currentIndex)
        updateChrome()
        showCurrent()
        view.window?.makeFirstResponder(canvas)
    }

    private func showEmpty() {
        items = []
        currentIndex = 0
        emptyState.isHidden = false
        filmstrip.isHidden = true
        filmstripHeight.constant = 0
        inspector.isHidden = true
        inspectorWidth.constant = 0
        gridContainer.isHidden = true
        canvas.clear()
        filmstrip.reload(items: [], selectedIndex: nil)
        gridVC.reload(items: [], selectedIndex: nil)
        topBar.update(folderName: folderURL?.lastPathComponent ?? "", fileName: "没有图片", index: 0, total: 0)
        statusBar.update(index: 0, total: 0, item: nil, zoomText: "", dimensions: nil)
    }

    // MARK: - Selection

    private func select(index: Int, show: Bool) {
        guard items.indices.contains(index) else { return }
        currentIndex = index
        let item = items[index]
        topBar.update(
            folderName: folderURL?.lastPathComponent ?? "",
            fileName: item.fileName,
            index: index,
            total: items.count
        )
        filmstrip.select(index: index, scroll: true)
        gridVC.select(index: index, scroll: true)
        if show && mode == .view {
            showCurrent()
        } else {
            updateStatus()
        }
    }

    private func showCurrent() {
        guard items.indices.contains(currentIndex) else { return }
        let index = currentIndex
        let item = items[index]
        let token = UUID()
        loadToken = token

        topBar.update(
            folderName: folderURL?.lastPathComponent ?? "",
            fileName: item.fileName,
            index: index,
            total: items.count
        )
        filmstrip.select(index: index, scroll: true)
        gridVC.select(index: index, scroll: true)

        let metadata = pipeline.metadata(for: item.url)
        inspector.update(item: item, metadata: metadata)
        updateStatus()

        let scale = view.window?.backingScaleFactor ?? 2
        let canvasWidth: CGFloat
        if view.bounds.width > 0 {
            canvasWidth = max(600, view.bounds.width - (inspectorVisible ? 300 : 0))
        } else {
            canvasWidth = max(canvas.bounds.width, 900)
        }
        let target = max(1400, min(3000, Int(canvasWidth * scale * 1.15)))

        if mode == .view {
            if let cachedFit = pipeline.cachedImage(for: item.url, maxPixel: target, allowEmbedded: false) {
                miraLog("cache hit \(item.fileName) @\(target)")
                canvas.display(image: cachedFit)
                updateStatus()
                prefetchNeighbors(target: target)
                return
            }
            if let preview = [420, 160].compactMap({ pipeline.cachedImage(for: item.url, maxPixel: $0, allowEmbedded: true) }).first {
                canvas.display(image: preview)
            } else {
                canvas.showPlaceholder(pixelSize: metadata?.pixelSize)
            }
        }

        let started = CFAbsoluteTimeGetCurrent()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let image = self.pipeline.image(for: item.url, maxPixel: target, allowEmbedded: false)
            let elapsed = (CFAbsoluteTimeGetCurrent() - started) * 1000
            miraLog(String(format: "decode %@ target=%d in %.1fms (%@)", item.fileName, target, elapsed, image.map { "\($0.width)x\($0.height)" } ?? "nil"))
            DispatchQueue.main.async {
                guard self.loadToken == token, self.currentIndex == index else { return }
                guard let image else {
                    self.toast.show("这张图无法解码")
                    return
                }
                if self.mode == .view {
                    self.canvas.display(image: image)
                }
                self.updateStatus()
                self.prefetchNeighbors(target: target)
            }
        }
    }

    private func loadDetail() {
        guard items.indices.contains(currentIndex), mode == .view else { return }
        let item = items[currentIndex]
        if let metadata = pipeline.metadata(for: item.url),
           max(metadata.pixelWidth, metadata.pixelHeight) <= 2000 {
            return
        }
        let index = currentIndex
        let detailStarted = CFAbsoluteTimeGetCurrent()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let detail = self.pipeline.image(for: item.url, maxPixel: 6144, allowEmbedded: false)
            miraLog(String(format: "detail %@ in %.1fms", item.fileName, (CFAbsoluteTimeGetCurrent() - detailStarted) * 1000))
            DispatchQueue.main.async {
                guard self.currentIndex == index, self.mode == .view, let detail else { return }
                self.canvas.displayDetail(detail)
            }
        }
    }

    private func prefetchNeighbors(target: Int) {
        guard items.count > 1 else { return }
        let index = currentIndex
        let neighbors = [-1, 1]
        let urls = neighbors.compactMap { offset -> URL? in
            let i = index + offset
            return items.indices.contains(i) ? items[i].url : nil
        }
        guard !urls.isEmpty else { return }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self else { return }
            for url in urls {
                _ = self.pipeline.image(for: url, maxPixel: target, allowEmbedded: false)
            }
        }
    }

    // MARK: - Navigation

    @objc func nextImage(_ sender: Any?) { step(1) }
    @objc func previousImage(_ sender: Any?) { step(-1) }

    private func step(_ delta: Int) {
        guard !items.isEmpty else { return }
        let next = currentIndex + delta
        guard items.indices.contains(next) else {
            toast.show(delta > 0 ? "已经是最后一张" : "已经是第一张")
            return
        }
        if mode == .grid {
            select(index: next, show: false)
            gridVC.select(index: next, scroll: true)
        } else {
            select(index: next, show: true)
        }
    }

    @objc func toggleGrid(_ sender: Any?) {
        guard !items.isEmpty else { return }
        setMode(mode == .grid ? .view : .grid)
    }

    private func setMode(_ newMode: DisplayMode) {
        guard newMode != mode else { return }
        if newMode == .grid {
            inspectorWasVisible = inspectorVisible
            mode = .grid
            gridContainer.isHidden = false
            emptyState.isHidden = true
            filmstrip.isHidden = true
            filmstripHeight.constant = 0
            inspector.isHidden = true
            inspectorWidth.constant = 0
            topBar.setGridActive(true)
            topBar.setInspectorActive(false)
            gridVC.reload(items: items, selectedIndex: currentIndex)
            gridVC.focus()
            updateStatus()
        } else {
            mode = .view
            gridContainer.isHidden = true
            emptyState.isHidden = true
            filmstrip.isHidden = false
            filmstripHeight.constant = 92
            inspectorVisible = inspectorWasVisible
            inspector.isHidden = !inspectorVisible
            inspectorWidth.constant = inspectorVisible ? 300 : 0
            topBar.setGridActive(false)
            topBar.setInspectorActive(inspectorVisible)
            gridVC.select(index: currentIndex, scroll: true)
            showCurrent()
            view.window?.makeFirstResponder(canvas)
        }
    }

    @objc func fitImage(_ sender: Any?) {
        guard mode == .view else { return }
        if canvas.isAtFit {
            canvas.actualSize()
        } else {
            canvas.fit(animated: true)
        }
        updateStatus()
    }

    @objc func actualSize(_ sender: Any?) {
        guard mode == .view else { return }
        canvas.actualSize()
        updateStatus()
    }

    @objc func toggleInspector(_ sender: Any?) {
        guard mode == .view, !items.isEmpty else { return }
        inspectorVisible.toggle()
        inspector.isHidden = !inspectorVisible
        inspectorWidth.constant = inspectorVisible ? 300 : 0
        topBar.setInspectorActive(inspectorVisible)
    }

    @objc func toggleFullScreen(_ sender: Any?) {
        view.window?.toggleFullScreen(nil)
    }

    @objc func toggleSlideshow(_ sender: Any?) {
        if slideshowTimer != nil {
            stopSlideshow()
            return
        }
        guard !items.isEmpty else { return }
        if mode == .grid { setMode(.view) }
        slideshowTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.currentIndex >= self.items.count - 1 {
                self.stopSlideshow()
            } else {
                self.step(1)
            }
        }
        toast.show("幻灯片播放中 · 按 S 停止")
    }

    private func stopSlideshow() {
        slideshowTimer?.invalidate()
        slideshowTimer = nil
    }

    // MARK: - File actions

    @objc func deleteCurrent(_ sender: Any?) {
        guard items.indices.contains(currentIndex) else { return }
        let index = currentIndex
        let item = items[index]
        miraLog("delete requested \(item.fileName)")
        NSWorkspace.shared.recycle([item.url]) { [weak self] mapping, error in
            miraLog("recycle completion error=\(String(describing: error)) mapping=\(mapping)")
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.showError("无法移到废纸篓", error)
                    return
                }
                let trashURL = mapping[item.url] ?? item.url
                self.deletedItems.append((item.url, trashURL))
                miraLog("deleted \(item.fileName) -> \(trashURL.path)")
                self.items.remove(at: index)
                if self.items.isEmpty {
                    self.showEmpty()
                    self.toast.show("已移到废纸篓")
                    return
                }
                self.currentIndex = min(index, self.items.count - 1)
                self.filmstrip.reload(items: self.items, selectedIndex: self.currentIndex)
                self.gridVC.reload(items: self.items, selectedIndex: self.currentIndex)
                if self.mode == .view {
                    self.showCurrent()
                } else {
                    self.updateChrome()
                }
                self.toast.show("已移到废纸篓 · ⌘Z 撤销")
            }
        }
    }

    @objc func undoDelete(_ sender: Any?) {
        guard let last = deletedItems.popLast() else {
            toast.show("没有可撤销的删除")
            return
        }
        do {
            try FileManager.default.moveItem(at: last.trash, to: last.original)
            miraLog("restored \(last.original.lastPathComponent)")
            toast.show("已恢复 \(last.original.lastPathComponent)")
            if let folderURL {
                openFolder(folderURL, selectFile: last.original)
            }
        } catch {
            showError("无法恢复文件", error)
        }
    }

    @objc func renameCurrent(_ sender: Any?) {
        guard items.indices.contains(currentIndex) else { return }
        let item = items[currentIndex]
        let alert = NSAlert()
        alert.messageText = "重命名"
        alert.informativeText = "只改文件名，不移动位置。"
        alert.addButton(withTitle: "重命名")
        alert.addButton(withTitle: "取消")
        let field = NSTextField(string: item.fileName)
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != item.fileName else { return }
        let newURL = item.url.deletingLastPathComponent().appendingPathComponent(newName)
        do {
            try FileManager.default.moveItem(at: item.url, to: newURL)
            if let folderURL {
                openFolder(folderURL, selectFile: newURL)
            }
            toast.show("已重命名为 \(newName)")
        } catch {
            showError("重命名失败", error)
        }
    }

    @objc func viewCurrent(_ sender: Any?) {
        guard items.indices.contains(currentIndex) else { return }
        if mode == .grid {
            setMode(.view)
        } else {
            showCurrent()
        }
    }

    @objc func editImage(_ sender: Any?) {
        if presentedViewControllers?.contains(where: { $0 is ImageEditorViewController }) == true {
            return
        }
        guard items.indices.contains(currentIndex) else {
            toast.show("先打开一张图片")
            return
        }
        let editor = ImageEditorViewController(sourceURL: items[currentIndex].url)
        editor.onSaved = { [weak self] url in
            self?.toast.show("已保存副本：\(url.lastPathComponent)")
        }
        presentAsSheet(editor)
    }

    @objc func copyFile(_ sender: Any?) {
        guard items.indices.contains(currentIndex) else { return }
        let item = items[currentIndex]
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.writeObjects([item.url as NSURL]) {
            toast.show("已复制文件")
        }
    }

    @objc func copyPath(_ sender: Any?) {
        guard items.indices.contains(currentIndex) else { return }
        let item = items[currentIndex]
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.url.path, forType: .string)
        toast.show("已复制文件路径")
    }

    @objc func copyImage(_ sender: Any?) {
        guard let image = canvas.image else {
            toast.show("还没有加载图片")
            return
        }
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.writeObjects([nsImage]) {
            toast.show("已复制图片")
        }
    }

    @objc func revealInFinder(_ sender: Any?) {
        guard items.indices.contains(currentIndex) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([items[currentIndex].url])
    }

    @objc func share(_ sender: Any?) {
        guard items.indices.contains(currentIndex) else { return }
        let picker = NSSharingServicePicker(items: [items[currentIndex].url])
        picker.show(relativeTo: topBar.shareButton.bounds, of: topBar.shareButton, preferredEdge: .minY)
    }

    @objc func sortByName(_ sender: Any?) { applySort(.name) }
    @objc func sortByDate(_ sender: Any?) { applySort(.date) }
    @objc func sortBySize(_ sender: Any?) { applySort(.size) }

    private func applySort(_ newSort: ImageSort) {
        guard let folderURL else { return }
        let selectedURL = items.indices.contains(currentIndex) ? items[currentIndex].url : nil
        sort = newSort
        do {
            let newItems = try FolderScanner.scan(folder: folderURL, sort: newSort, ascending: ascending)
            items = newItems
            currentIndex = selectedURL.flatMap { target in
                newItems.firstIndex { $0.url.standardizedFileURL == target.standardizedFileURL }
            } ?? 0
            filmstrip.reload(items: items, selectedIndex: currentIndex)
            gridVC.reload(items: items, selectedIndex: currentIndex)
            if mode == .view { showCurrent() } else { updateChrome() }
        } catch {
            showError("排序失败", error)
        }
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.handleKey(event) { return nil }
            return event
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.window == view.window else { return false }
        if event.window?.firstResponder is NSTextView { return false }
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) || event.modifierFlags.contains(.option) {
            return false
        }

        let keyCode = event.keyCode
        let shift = event.modifierFlags.contains(.shift)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

        switch keyCode {
        case 123, 126: // left, up
            if mode == .grid { gridVC.moveSelection(by: -1) } else { step(-1) }
            return true
        case 124, 125: // right, down
            if mode == .grid { gridVC.moveSelection(by: 1) } else { step(1) }
            return true
        case 49: // space
            if mode == .grid {
                gridVC.openSelection()
            } else {
                step(shift ? -1 : 1)
            }
            return true
        case 36, 76: // return
            if mode == .grid { gridVC.openSelection() }
            return true
        case 51, 117: // delete
            deleteCurrent(nil)
            return true
        case 53: // esc
            if mode == .grid {
                setMode(.view)
            } else if view.window?.styleMask.contains(.fullScreen) == true {
                view.window?.toggleFullScreen(nil)
            }
            return true
        default:
            break
        }

        switch chars {
        case "g":
            toggleGrid(nil)
        case "z":
            fitImage(nil)
        case "1":
            actualSize(nil)
        case "0":
            canvas.fit(animated: true)
            updateStatus()
        case "i":
            toggleInspector(nil)
        case "f":
            toggleFullScreen(nil)
        case "s":
            toggleSlideshow(nil)
        case "?":
            showShortcuts(nil)
        case "+", "=":
            if mode == .view {
                canvas.zoom(to: canvas.zoom * 1.25, anchorInView: CGPoint(x: canvas.bounds.midX, y: canvas.bounds.midY))
                updateStatus()
            }
        case "-":
            if mode == .view {
                canvas.zoom(to: canvas.zoom / 1.25, anchorInView: CGPoint(x: canvas.bounds.midX, y: canvas.bounds.midY))
                updateStatus()
            }
        default:
            return false
        }
        return true
    }

    @objc func showShortcuts(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Mira 快捷键"
        alert.informativeText = """
        ← → / Space    上一张 / 下一张
        G              网格 / 查看
        Enter          从网格打开
        Z              适应 / 100%
        1 / 0          100% / 适应
        I              信息面板
        ⌘E             编辑图片
        F              全屏
        S              幻灯片
        Delete         移到废纸篓
        ⌘Z             撤销删除
        ⇧⌘R            在 Finder 中显示
        ⌘O             打开
        ?              显示这个列表
        """
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    // MARK: - Chrome

    private func updateChrome() {
        guard items.indices.contains(currentIndex) else {
            topBar.update(folderName: folderURL?.lastPathComponent ?? "", fileName: "没有图片", index: 0, total: 0)
            return
        }
        let item = items[currentIndex]
        topBar.update(
            folderName: folderURL?.lastPathComponent ?? "",
            fileName: item.fileName,
            index: currentIndex,
            total: items.count
        )
        topBar.setGridActive(mode == .grid)
        topBar.setInspectorActive(inspectorVisible)
        updateStatus()
    }

    private func updateStatus() {
        let item = items.indices.contains(currentIndex) ? items[currentIndex] : nil
        let zoomText: String
        if canvas.image == nil {
            zoomText = ""
        } else if canvas.isAtFit {
            zoomText = "适应"
        } else {
            zoomText = String(format: "%.0f%%", canvas.zoom * 100)
        }
        topBar.setFitTitle(canvas.isAtFit ? "100%" : "适应")
        let originalSize = item.flatMap { pipeline.metadata(for: $0.url)?.pixelSize }
        statusBar.update(
            index: currentIndex,
            total: items.count,
            item: item,
            zoomText: zoomText,
            dimensions: originalSize
        )
    }

    private func showError(_ title: String, _ error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
