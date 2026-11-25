import AppKit
import PinShellCore

/// PinShell 控制台：原生侧边栏 + 详情布局。
/// 模板预览/应用/编辑、MCP 2.0 接入信息。
@MainActor
final class ConsoleController: NSObject, NSWindowDelegate, NSToolbarDelegate {
    private let windowController: OverlayWindowController
    private(set) var window: NSWindow!
    private lazy var libraryService = TemplateLibraryService(windowController: windowController)

    private let splitController = NSSplitViewController()
    private let sidebar = ConsoleSidebarViewController()
    private let detail = ConsoleDetailViewController()

    private var showHideItem: NSToolbarItem?
    private var editorSheet: TemplateEditorSheetController?
    private var lastStatusFile: String?
    private var hasShown = false
    private var templatesWatcher: TemplateDirectoryWatcher?
    private var lastDirectTemplatesChange = Date.distantPast
    private var templatesRefreshWork: DispatchWorkItem?

    /// 官网模板库：支持从网页一键安装到 PinShell（pinshell:// 深链）。
    private static let onlineLibraryURL = URL(
        string: "https://pinshell.looplooptech.com/templates/")!

    init(windowController: OverlayWindowController) {
        self.windowController = windowController
        super.init()
        buildWindow()
        wireActions()
        installObservers()
        installShortcutHandling()
        installTemplatesWatcher()
        libraryService.onChange = { [weak self] in
            self?.libraryChanged()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        templatesWatcher?.stop()
    }

    /// 控制台快捷键：默认 ⌘1 模板、⌘2 MCP、⌘3 关于、⌘4 在线模板库、⌘5 通用、⌘E 编辑；
    /// 组合可在「快捷键」中修改，统一由 ShortcutDispatcher 分发。
    private func installShortcutHandling() {
        let dispatcher = ShortcutDispatcher.shared
        for action in ShortcutAction.allCases where action.scope == .console {
            dispatcher.register(action) { [weak self] in self?.performShortcut(action) }
        }
        dispatcher.installConsoleMonitor(for: window)
    }

    private func performShortcut(_ action: ShortcutAction) {
        switch action {
        case .showTemplates:
            sidebar.selectFirstTemplate()
        case .editTemplate:
            editSelected()
        default:
            if let page = action.page {
                sidebar.select(page)
            }
        }
    }

    // MARK: - 装配

    private func buildWindow() {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 620),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                           backing: .buffered, defer: false)
        win.title = NSLocalizedString("console.title", comment: "")
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.titlebarSeparatorStyle = .none
        win.toolbarStyle = .unified
        win.minSize = NSSize(width: 780, height: 540)
        win.isReleasedWhenClosed = false
        win.isOpaque = false
        win.backgroundColor = .clear
        win.delegate = self
        win.setFrameAutosaveName("PinShell.ConsoleWindow")
        window = win

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 300
        sidebarItem.canCollapse = true
        splitController.addSplitViewItem(sidebarItem)
        splitController.addSplitViewItem(NSSplitViewItem(viewController: detail))
        splitController.splitView.autosaveName = "PinShell.ConsoleSplit"
        win.contentViewController = splitController

        let toolbar = NSToolbar(identifier: NSToolbar.Identifier("PinShell.ConsoleToolbar"))
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        win.toolbar = toolbar
    }

    private func wireActions() {
        sidebar.onSelectTemplate = { [weak self] item in
            self?.detail.showTemplate(item)
            self?.window.toolbar?.validateVisibleItems()
        }
        sidebar.onSelectPage = { [weak self] page in
            self?.show(page)
        }
        detail.onOpenLibrary = { [weak self] in
            self?.sidebar.select(.library)
        }
        detail.onOpenInstalled = { [weak self] file in
            self?.openInstalledTemplate(file)
        }
        sidebar.onApplyTemplate = { [weak self] item in
            self?.apply(item)
        }
        sidebar.onEditTemplate = { [weak self] item in
            self?.edit(item)
        }
        sidebar.onDeleteTemplate = { [weak self] item in
            self?.confirmDelete(item)
        }
        detail.onApply = { [weak self] item in
            self?.apply(item)
        }
        detail.onDelete = { [weak self] item in
            self?.confirmDelete(item)
        }
        detail.onEdit = { [weak self] item in
            self?.edit(item)
        }
        detail.authorProvider = { [weak self] file in
            self?.libraryService.author(forFile: file)
        }
        detail.versionProvider = { [weak self] file in
            self?.libraryService.installedVersion(forFile: file)
        }
    }

    private func installObservers() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(statusChanged),
                           name: .pinshellStatusChanged, object: nil)
        center.addObserver(self, selector: #selector(statusChanged),
                           name: .pinshellPassthroughChanged, object: nil)
        center.addObserver(self, selector: #selector(templatesChanged(_:)),
                           name: .pinshellTemplatesChanged, object: nil)
        center.addObserver(self, selector: #selector(templateInstalled(_:)),
                           name: .pinshellTemplateInstalled, object: nil)
    }

    @objc private func templateInstalled(_ notification: Notification) {
        // Installing from the library must not navigate away; keep the user in the library.
        sidebar.select(.library)
    }

    private func installTemplatesWatcher() {
        templatesWatcher = TemplateDirectoryWatcher(
            directory: TemplateStore.userTemplatesDirectory()) { [weak self] in
            self?.templatesDirectoryChanged()
        }
    }

    @objc private func templatesChanged(_ notification: Notification) {
        lastDirectTemplatesChange = Date()
        scheduleTemplatesRefresh()
    }

    /// 目录轮询比直接通知晚约 0.6s：刚处理过直接通知时跳过本次重复刷新。
    private func templatesDirectoryChanged() {
        guard Date().timeIntervalSince(lastDirectTemplatesChange) >= 1 else { return }
        libraryService.revalidateLocalFiles()
        scheduleTemplatesRefresh()
    }

    private func scheduleTemplatesRefresh() {
        templatesRefreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.refreshTemplatesFromDisk()
        }
        templatesRefreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    /// 模板目录变化：静默刷新侧栏；正在预览的模板若被改写则重新加载。
    private func refreshTemplatesFromDisk() {
        guard window.isVisible else { return }
        let templates = sidebar.refreshTemplatesKeepingSelection()
        if templates.isEmpty {
            syncDetailToSidebar()
            return
        }
        if sidebar.isLibrarySelected {
            syncDetailToSidebar()
            return
        }
        if let current = detail.currentTemplate,
           let fresh = templates.first(where: {
               $0.url.standardizedFileURL == current.url.standardizedFileURL
           }) {
            detail.showTemplate(fresh)
        }
    }

    // MARK: - 窗口生命周期

    func show() {
        templatesWatcher?.start()
        // 目录同时提供本地模板的作者信息；后台加载，失败时不影响控制台。
        Task { await libraryService.ensureLoaded() }
        window.contentView?.layoutSubtreeIfNeeded()
        sidebar.reloadTemplates(selecting: windowController.currentURL)
        sidebar.updateAppliedTemplate(windowController.currentURL)
        syncDetailToSidebar()
        lastStatusFile = windowController.status()["file"]?.stringValue
        if !hasShown {
            window.setContentSize(NSSize(width: 940, height: 620))
            window.center()
            hasShown = true
        } else if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }) {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        sidebar.focusList()
        refreshStatus()
    }

    func windowWillClose(_ notification: Notification) {
        templatesWatcher?.stop()
    }

    @objc private func statusChanged() {
        refreshStatus()
    }

    private func refreshStatus() {
        // 隐藏时不刷新：状态通知在拖动/切换时很密集，显示前 show() 会补一次完整刷新
        guard window.isVisible else { return }
        let status = windowController.status()

        // 悬浮窗换文件时，让侧栏跟随当前文件（首次打开时也靠它兜底加载时序）
        let file = status["file"]?.stringValue
        if file != lastStatusFile {
            lastStatusFile = file
            sidebar.reloadTemplates(selecting: windowController.currentURL)
            syncDetailToSidebar()
        }
        sidebar.updateAppliedTemplate(windowController.currentURL)

        detail.refreshStatus(status)

        let visible = status["visible"]?.boolValue ?? false
        showHideItem?.image = Self.toolbarImage(visible ? "eye.slash" : "eye")
        showHideItem?.label = visible
            ? NSLocalizedString("console.toolbar.hide", comment: "")
            : NSLocalizedString("console.toolbar.show", comment: "")
        showHideItem?.toolTip = showHideItem?.label
        window.toolbar?.validateVisibleItems()
    }

    // MARK: - 动作

    private func apply(_ item: TemplateItem) {
        windowController.loadHTML(item.url)
        sidebar.updateAppliedTemplate(item.url)
        refreshStatus()
    }

    private func show(_ page: ConsolePage) {
        detail.showPage(page, service: libraryService)
        window.toolbar?.validateVisibleItems()
    }

    /// 官网深链：打开控制台与模板库，并安装指定模板。
    func installTemplateFromLibrary(id: String, catalogURL: URL) {
        show()
        sidebar.select(.library)
        Task { @MainActor in
            await detail.installTemplateFromLibrary(id: id,
                                                    catalogURL: catalogURL,
                                                    service: libraryService)
        }
    }

    private func libraryChanged() {
        sidebar.updateLibraryBadge(libraryService.updateCount)
        detail.refreshLibrary()
        detail.refreshLibraryMetadata()
        detail.refreshGeneral()
    }

    private func syncDetailToSidebar() {
        if sidebar.isLibrarySelected {
            if !detail.isShowingLibrary {
                detail.showPage(.library, service: libraryService)
            }
        } else if !sidebar.hasTemplates,
                  !detail.isShowingLibrary,
                  !detail.isShowingServicePage {
            detail.showEmpty()
        }
    }

    private func openInstalledTemplate(_ file: String) {
        guard let item = TemplateStore.load().first(where: { $0.file == file }) else {
            return
        }
        sidebar.reloadTemplates(selecting: item.url)
        apply(item)
    }

    private func edit(_ item: TemplateItem) {
        let sheet = TemplateEditorSheetController(
            item: item,
            libraryVersion: libraryService.installedVersion(forFile: item.file))
        sheet.onDismiss = { [weak self] in self?.editorSheet = nil }
        sheet.onSave = { [weak self] edit in
            do {
                try HTMLTemplateEditor.apply(edit, to: item.url)
            } catch {
                return .failure(error)
            }

            guard let self else { return .success(()) }
            // 已直接刷新侧栏与预览；标记为直接变更，跳过目录轮询触发的重复刷新。
            self.lastDirectTemplatesChange = Date()
            self.sidebar.reloadTemplates(selecting: item.url)
            if self.windowController.currentURL?.standardizedFileURL == item.url.standardizedFileURL {
                self.windowController.loadHTML(item.url)
            }
            self.refreshStatus()
            return .success(())
        }
        editorSheet = sheet
        sheet.present(in: window)
    }

    /// 删除前确认：模板库安装的模板说明可重新下载，本地模板提示不可撤销。
    private func confirmDelete(_ item: TemplateItem) {
        let alert = NSAlert()
        alert.messageText = String(format: NSLocalizedString("console.delete.title", comment: ""),
                                   item.name)
        let isLibrary = libraryService.installedVersion(forFile: item.file) != nil
        alert.informativeText = isLibrary
            ? NSLocalizedString("console.delete.libraryInfo", comment: "")
            : NSLocalizedString("console.delete.info", comment: "")
        alert.alertStyle = .warning
        let confirm = alert.addButton(withTitle: NSLocalizedString("console.delete.confirm", comment: ""))
        confirm.hasDestructiveAction = true
        let cancel = alert.addButton(withTitle: NSLocalizedString("console.delete.cancel", comment: ""))
        cancel.keyEquivalent = "\u{1b}"

        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.delete(item)
        }
    }

    private func delete(_ item: TemplateItem) {
        let isCurrent = windowController.currentURL?.standardizedFileURL
            == item.url.standardizedFileURL
        do {
            try TemplateStore.deleteTemplate(at: item.url)
            if isCurrent { windowController.clearHTML() }
            sidebar.reloadTemplates(selecting: nil)
            sidebar.updateAppliedTemplate(windowController.currentURL)
            syncDetailToSidebar()
            templatesRefreshWork?.cancel()   // 已直接刷新，跳过通知触发的重复刷新
            refreshStatus()
        } catch {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("console.delete.errorTitle", comment: "")
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: NSLocalizedString("console.error.ok", comment: ""))
            alert.beginSheetModal(for: window)
        }
    }

    @objc private func openOnlineLibrary() {
        NSWorkspace.shared.open(Self.onlineLibraryURL)
    }

    @objc private func revealTemplatesFolder() {
        NSWorkspace.shared.open(TemplateStore.userTemplatesDirectory())
    }

    @objc private func toggleOverlayVisibility() {
        windowController.toggleVisibility()
        refreshStatus()
    }

    @objc private func reloadCurrent() {
        windowController.reloadHTML()
        refreshStatus()
    }

    @objc private func editSelected() {
        guard let item = detail.currentTemplate else { return }
        edit(item)
    }

    // MARK: - NSToolbarDelegate

    private enum ToolbarID {
        static let showHide = NSToolbarItem.Identifier("PinShell.Console.ShowHide")
        static let reload = NSToolbarItem.Identifier("PinShell.Console.Reload")
        static let templates = NSToolbarItem.Identifier("PinShell.Console.Templates")
    }

    /// 工具栏图标按符号各自的字号渲染（默认 17pt）。SF Symbol 的字形留白不同，
    /// 用统一默认尺寸时圆形箭头/省略号明显压过扁平的眼镜，按符号微调后视觉才等大。
    /// 左右再留出透明边距：系统工具栏项间距不可调，用图像内边距换出更疏朗的节奏；
    /// 菜单项的箭头也会跟着远离圆形图标。
    private static func toolbarImage(_ symbol: String,
                                     pointSize: CGFloat = 17,
                                     horizontalPadding: CGFloat = 4) -> NSImage? {
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize,
                                                                 weight: .regular))
        else { return nil }
        guard horizontalPadding > 0 else { return image }

        let glyph = image.size
        let canvas = NSSize(width: glyph.width + horizontalPadding * 2,
                            height: glyph.height)
        let padded = NSImage(size: canvas, flipped: false) { _ in
            image.draw(in: NSRect(x: horizontalPadding,
                                  y: 0,
                                  width: glyph.width,
                                  height: glyph.height))
            return true
        }
        padded.isTemplate = true
        return padded
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .flexibleSpace, ToolbarID.showHide, ToolbarID.reload,
         ToolbarID.templates]
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if itemIdentifier == ToolbarID.templates {
            return makeTemplatesMenuToolbarItem(itemIdentifier)
        }

        struct Spec {
            let titleKey: String
            let symbol: String
            var pointSize: CGFloat = 17
            let action: Selector
        }
        let specs: [NSToolbarItem.Identifier: Spec] = [
            ToolbarID.showHide: Spec(titleKey: "console.toolbar.hide",
                                     symbol: "eye.slash",
                                     action: #selector(toggleOverlayVisibility)),
            ToolbarID.reload: Spec(titleKey: "console.toolbar.reload",
                                   symbol: "arrow.clockwise",
                                   pointSize: 12,
                                   action: #selector(reloadCurrent)),
        ]
        guard let spec = specs[itemIdentifier] else { return nil }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.isBordered = false
        item.target = self
        item.label = NSLocalizedString(spec.titleKey, comment: "")
        item.paletteLabel = item.label
        item.toolTip = item.label
        item.image = Self.toolbarImage(spec.symbol, pointSize: spec.pointSize)
        item.action = spec.action
        if itemIdentifier == ToolbarID.showHide {
            showHideItem = item
        }
        return item
    }

    /// 模板操作菜单：在线模板库 / 打开模板目录。
    private func makeTemplatesMenuToolbarItem(_ identifier: NSToolbarItem.Identifier) -> NSToolbarItem {
        let item = NSMenuToolbarItem(itemIdentifier: identifier)
        item.label = NSLocalizedString("console.toolbar.templates", comment: "")
        item.paletteLabel = item.label
        item.toolTip = item.label
        item.image = Self.toolbarImage("ellipsis.circle", pointSize: 15)
        item.isBordered = false
        item.showsIndicator = true

        let menu = NSMenu()
        let library = NSMenuItem(title: NSLocalizedString("console.toolbar.onlineLibrary", comment: ""),
                                 action: #selector(openOnlineLibrary), keyEquivalent: "")
        library.target = self
        library.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil)
        menu.addItem(library)

        let openFolder = NSMenuItem(title: NSLocalizedString("console.toolbar.revealFolder", comment: ""),
                                    action: #selector(revealTemplatesFolder), keyEquivalent: "")
        openFolder.target = self
        openFolder.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        menu.addItem(openFolder)

        item.menu = menu
        return item
    }
}
