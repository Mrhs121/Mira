import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var browser: BrowserViewController?
    private var pendingURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()

        let browser = BrowserViewController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = browser
        window.title = "Mira"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.backgroundColor = NSColor(calibratedWhite: 0.075, alpha: 1)
        window.minSize = NSSize(width: 820, height: 560)
        window.setFrameAutosaveName("MiraMainWindow")
        window.setContentSize(NSSize(width: 1180, height: 760))
        window.center()
        window.makeKeyAndOrderFront(nil)

        self.browser = browser
        self.window = window

        if !pendingURLs.isEmpty {
            browser.open(urls: pendingURLs)
            pendingURLs.removeAll()
        } else if let path = CommandLine.arguments.dropFirst().first(where: {
            !$0.hasPrefix("-") && FileManager.default.fileExists(atPath: $0)
        }) {
            browser.open(urls: [URL(fileURLWithPath: path)])
        }

        NSApp.activate(ignoringOtherApps: true)
        installDebugHooks(browser: browser)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard !urls.isEmpty else { return }
        if let browser {
            browser.open(urls: urls)
        } else {
            pendingURLs.append(contentsOf: urls)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func installDebugHooks(browser: BrowserViewController) {
        let env = ProcessInfo.processInfo.environment
        if let path = env["MIRA_OPEN"], FileManager.default.fileExists(atPath: path) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                browser.open(urls: [URL(fileURLWithPath: path)])
            }
        }
        if env["MIRA_GRID"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                browser.toggleGrid(nil)
            }
        }
        if env["MIRA_ZOOM"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                browser.actualSize(nil)
            }
        }
        if env["MIRA_NEXT"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                browser.nextImage(nil)
            }
        }
        if env["MIRA_DELETE"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                browser.deleteCurrent(nil)
            }
        }
        if env["MIRA_UNDO"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
                browser.undoDelete(nil)
            }
        }
        if env["MIRA_EDIT"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                browser.editImage(nil)
            }
        }
        guard let snapshot = env["MIRA_SNAPSHOT"] else { return }
        let delay = Double(env["MIRA_SNAPSHOT_DELAY"] ?? "") ?? 2.2
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.writeSnapshot(to: snapshot)
        }
    }

    private func writeSnapshot(to path: String) {
        let targetWindow = window?.attachedSheet ?? window
        guard let targetWindow, let view = targetWindow.contentView else { return }
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0,
              let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
        if ProcessInfo.processInfo.environment["MIRA_QUIT_AFTER_SNAPSHOT"] == "1" {
            NSApp.terminate(nil)
        }
    }

    // MARK: - Menu actions

    @objc private func openDocumentAction(_ sender: Any?) { browser?.openDocument(sender) }
    @objc private func toggleGridAction(_ sender: Any?) { browser?.toggleGrid(sender) }
    @objc private func toggleInspectorAction(_ sender: Any?) { browser?.toggleInspector(sender) }
    @objc private func fitAction(_ sender: Any?) { browser?.fitImage(sender) }
    @objc private func actualAction(_ sender: Any?) { browser?.actualSize(sender) }
    @objc private func fullScreenAction(_ sender: Any?) { browser?.toggleFullScreen(sender) }
    @objc private func slideshowAction(_ sender: Any?) { browser?.toggleSlideshow(sender) }
    @objc private func renameAction(_ sender: Any?) { browser?.renameCurrent(sender) }
    @objc private func deleteAction(_ sender: Any?) { browser?.deleteCurrent(sender) }
    @objc private func undoDeleteAction(_ sender: Any?) { browser?.undoDelete(sender) }
    @objc private func copyImageAction(_ sender: Any?) { browser?.copyImage(sender) }
    @objc private func editAction(_ sender: Any?) { browser?.editImage(sender) }
    @objc private func revealAction(_ sender: Any?) { browser?.revealInFinder(sender) }
    @objc private func shareAction(_ sender: Any?) { browser?.share(sender) }
    @objc private func shortcutsAction(_ sender: Any?) { browser?.showShortcuts(sender) }
    @objc private func sortNameAction(_ sender: Any?) { browser?.sortByName(sender) }
    @objc private func sortDateAction(_ sender: Any?) { browser?.sortByDate(sender) }
    @objc private func sortSizeAction(_ sender: Any?) { browser?.sortBySize(sender) }

    // MARK: - Menu

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "关于 Mira", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let hide = appMenu.addItem(withTitle: "隐藏 Mira", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hide.keyEquivalentModifierMask = [.command]
        let hideOthers = appMenu.addItem(withTitle: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "显示全部", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 Mira", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "文件")
        fileItem.submenu = fileMenu
        let open = fileMenu.addItem(withTitle: "打开…", action: #selector(openDocumentAction(_:)), keyEquivalent: "o")
        open.target = self
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editItem.submenu = editMenu
        let undo = editMenu.addItem(withTitle: "撤销删除", action: #selector(undoDeleteAction(_:)), keyEquivalent: "z")
        undo.target = self
        let copy = editMenu.addItem(withTitle: "复制图片", action: #selector(copyImageAction(_:)), keyEquivalent: "c")
        copy.target = self
        editMenu.addItem(.separator())
        let selectAll = editMenu.addItem(withTitle: "全选", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a")
        selectAll.target = nil

        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "显示")
        viewItem.submenu = viewMenu
        let grid = viewMenu.addItem(withTitle: "网格 / 查看", action: #selector(toggleGridAction(_:)), keyEquivalent: "g")
        grid.target = self
        grid.keyEquivalentModifierMask = []
        let info = viewMenu.addItem(withTitle: "信息面板", action: #selector(toggleInspectorAction(_:)), keyEquivalent: "i")
        info.target = self
        info.keyEquivalentModifierMask = []
        viewMenu.addItem(.separator())
        let fit = viewMenu.addItem(withTitle: "适应窗口 / 100%", action: #selector(fitAction(_:)), keyEquivalent: "z")
        fit.target = self
        fit.keyEquivalentModifierMask = []
        let actual = viewMenu.addItem(withTitle: "实际像素 100%", action: #selector(actualAction(_:)), keyEquivalent: "1")
        actual.target = self
        actual.keyEquivalentModifierMask = []
        let fullscreen = viewMenu.addItem(withTitle: "进入全屏幕", action: #selector(fullScreenAction(_:)), keyEquivalent: "f")
        fullscreen.target = self
        fullscreen.keyEquivalentModifierMask = []
        let slideshow = viewMenu.addItem(withTitle: "幻灯片", action: #selector(slideshowAction(_:)), keyEquivalent: "s")
        slideshow.target = self
        slideshow.keyEquivalentModifierMask = []
        viewMenu.addItem(.separator())
        let sortMenu = NSMenu(title: "排序")
        let sortItem = NSMenuItem(title: "排序", action: nil, keyEquivalent: "")
        sortItem.submenu = sortMenu
        viewMenu.addItem(sortItem)
        [("按名称", #selector(sortNameAction(_:))), ("按修改时间", #selector(sortDateAction(_:))), ("按大小", #selector(sortSizeAction(_:)))].forEach { title, action in
            let item = sortMenu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
        }

        let imageItem = NSMenuItem()
        mainMenu.addItem(imageItem)
        let imageMenu = NSMenu(title: "图片")
        imageItem.submenu = imageMenu
        let edit = imageMenu.addItem(withTitle: "编辑图片…", action: #selector(editAction(_:)), keyEquivalent: "e")
        edit.target = self
        edit.keyEquivalentModifierMask = [.command]
        imageMenu.addItem(.separator())
        let rename = imageMenu.addItem(withTitle: "重命名…", action: #selector(renameAction(_:)), keyEquivalent: "")
        rename.target = self
        let delete = imageMenu.addItem(withTitle: "移到废纸篓", action: #selector(deleteAction(_:)), keyEquivalent: "")
        delete.target = self
        let reveal = imageMenu.addItem(withTitle: "在 Finder 中显示", action: #selector(revealAction(_:)), keyEquivalent: "r")
        reveal.keyEquivalentModifierMask = [.command, .shift]
        reveal.target = self
        let share = imageMenu.addItem(withTitle: "分享…", action: #selector(shareAction(_:)), keyEquivalent: "")
        share.target = self

        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "窗口")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu

        let helpItem = NSMenuItem()
        mainMenu.addItem(helpItem)
        let helpMenu = NSMenu(title: "帮助")
        helpItem.submenu = helpMenu
        let shortcuts = helpMenu.addItem(withTitle: "Mira 快捷键", action: #selector(shortcutsAction(_:)), keyEquivalent: "?")
        shortcuts.target = self
        shortcuts.keyEquivalentModifierMask = []

        NSApp.mainMenu = mainMenu
    }
}
