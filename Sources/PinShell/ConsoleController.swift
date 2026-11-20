import AppKit
import PinShellCore

/// PinShell 控制台：原生侧边栏 + 详情布局。
/// 模板预览/应用/编辑、MCP 2.0 接入信息；窗口页与事件页已移除。
final class ConsoleController: NSObject, NSWindowDelegate, NSToolbarDelegate {
    private let windowController: OverlayWindowController
    private(set) var window: NSWindow!

    private let splitController = NSSplitViewController()
    private let sidebar = ConsoleSidebarViewController()
    private let detail = ConsoleDetailViewController()

    private var showHideItem: NSToolbarItem?
    private var editorSheet: TemplateEditorSheetController?
    private var keyMonitor: Any?
    private var lastStatusFile: String?
    private var hasShown = false
    private var templatesWatcher: TemplateDirectoryWatcher?
    private var lastDirectTemplatesChange = Date.distantPast
    private var templatesRefreshWork: DispatchWorkItem?

    init(windowController: OverlayWindowController) {
        self.windowController = windowController
        super.init()
        buildWindow()
        wireActions()
        installObservers()
        installKeyMonitor()
        installTemplatesWatcher()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        templatesWatcher?.stop()
    }

    /// 控制台快捷键：⌘1 模板、⌘2 MCP、⌘3 关于、⌘E 编辑当前模板。
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window.isKeyWindow,
                  event.modifierFlags.contains(.command),
                  let key = event.charactersIgnoringModifiers?.lowercased() else {
                return event
            }
            switch key {
            case "1":
                self.sidebar.selectFirstTemplate()
                return nil
            case "2":
                self.sidebar.selectMCP()
                return nil
            case "3":
                self.sidebar.selectAbout()
                return nil
            case "e":
                self.editSelected()
                return nil
            default:
                return event
            }
        }
    }

    // MARK: - 装配

    private func buildWindow() {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                           backing: .buffered, defer: false)
        win.title = NSLocalizedString("console.title", comment: "")
        win.titlebarAppearsTransparent = true
        win.toolbarStyle = .unified
        win.minSize = NSSize(width: 780, height: 540)
        win.isReleasedWhenClosed = false
        win.isOpaque = false
        win.backgroundColor = .clear
        win.delegate = self
        win.setFrameAutosaveName("PinShell.ConsoleWindow")
        window = win

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 235
        sidebarItem.maximumThickness = 320
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
        sidebar.onSelectMCP = { [weak self] in
            self?.detail.showMCP()
            self?.window.toolbar?.validateVisibleItems()
        }
        sidebar.onSelectAbout = { [weak self] in
            self?.detail.showAbout()
            self?.window.toolbar?.validateVisibleItems()
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
    }

    private func installObservers() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(statusChanged),
                           name: .pinshellStatusChanged, object: nil)
        center.addObserver(self, selector: #selector(statusChanged),
                           name: .pinshellPassthroughChanged, object: nil)
        center.addObserver(self, selector: #selector(templatesChanged(_:)),
                           name: .pinshellTemplatesChanged, object: nil)
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
            detail.showEmpty()
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
        window.contentView?.layoutSubtreeIfNeeded()
        sidebar.reloadTemplates(selecting: windowController.currentURL)
        if !sidebar.hasTemplates { detail.showEmpty() }
        lastStatusFile = windowController.status()["file"]?.stringValue
        if !hasShown {
            window.setContentSize(NSSize(width: 900, height: 560))
            window.center()
            hasShown = true
        } else if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }) {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
        }

        detail.refreshStatus(status)

        let visible = status["visible"]?.boolValue ?? false
        showHideItem?.image = NSImage(systemSymbolName: visible ? "eye.slash" : "eye",
                                      accessibilityDescription: nil)
        showHideItem?.label = visible
            ? NSLocalizedString("console.toolbar.hide", comment: "")
            : NSLocalizedString("console.toolbar.show", comment: "")
        showHideItem?.toolTip = showHideItem?.label
        window.toolbar?.validateVisibleItems()
    }

    // MARK: - 动作

    private func apply(_ item: TemplateItem) {
        windowController.loadHTML(item.url)
        refreshStatus()
    }

    private func edit(_ item: TemplateItem) {
        let sheet = TemplateEditorSheetController(item: item)
        sheet.onDismiss = { [weak self] in self?.editorSheet = nil }
        sheet.onSave = { [weak self] edit in
            do {
                try HTMLTemplateEditor.apply(edit, to: item.url)
            } catch {
                return .failure(error)
            }

            guard let self else { return .success(()) }
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

    /// 删除前确认：内置模板会说明可恢复，普通模板提示不可撤销。
    private func confirmDelete(_ item: TemplateItem) {
        let alert = NSAlert()
        alert.messageText = String(format: NSLocalizedString("console.delete.title", comment: ""),
                                   item.name)
        let isBuiltin = TemplateStore.isBuiltinTemplate(named: item.file)
        alert.informativeText = isBuiltin
            ? NSLocalizedString("console.delete.builtinInfo", comment: "")
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
            if !sidebar.hasTemplates { detail.showEmpty() }
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

    @objc private func restoreBuiltins() {
        TemplateStore.restoreBuiltins()
        sidebar.reloadTemplates(selecting: nil)
        templatesRefreshWork?.cancel()   // 已直接刷新，跳过通知触发的重复刷新
        refreshStatus()
    }

    @objc private func revealTemplatesFolder() {
        NSWorkspace.shared.open(TemplateStore.userTemplatesDirectory())
    }

    /// 工具栏文件夹图标：定位并选中当前模板的 HTML 文件；未选模板时退回模板目录。
    @objc private func revealSelected() {
        if let item = detail.currentTemplate {
            NSWorkspace.shared.activateFileViewerSelecting([item.url])
        } else {
            NSWorkspace.shared.open(TemplateStore.userTemplatesDirectory())
        }
    }

    @objc private func toggleOverlayVisibility() {
        if windowController.panel.isVisible {
            windowController.hideWindow()
        } else {
            windowController.showWindow()
        }
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
        static let edit = NSToolbarItem.Identifier("PinShell.Console.Edit")
        static let folder = NSToolbarItem.Identifier("PinShell.Console.Folder")
        static let templates = NSToolbarItem.Identifier("PinShell.Console.Templates")
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .flexibleSpace, ToolbarID.showHide, ToolbarID.reload,
         ToolbarID.edit, ToolbarID.folder, ToolbarID.templates]
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if itemIdentifier == ToolbarID.templates {
            return makeTemplatesMenuToolbarItem(itemIdentifier)
        }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.isBordered = true
        item.target = self

        switch itemIdentifier {
        case ToolbarID.showHide:
            item.label = NSLocalizedString("console.toolbar.hide", comment: "")
            item.paletteLabel = item.label
            item.toolTip = item.label
            item.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: nil)
            item.action = #selector(toggleOverlayVisibility)
            showHideItem = item

        case ToolbarID.reload:
            item.label = NSLocalizedString("console.toolbar.reload", comment: "")
            item.paletteLabel = item.label
            item.toolTip = item.label
            item.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
            item.action = #selector(reloadCurrent)

        case ToolbarID.edit:
            item.label = NSLocalizedString("console.toolbar.edit", comment: "")
            item.paletteLabel = item.label
            item.toolTip = item.label
            item.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil)
            item.action = #selector(editSelected)

        case ToolbarID.folder:
            item.label = NSLocalizedString("console.toolbar.folder", comment: "")
            item.paletteLabel = item.label
            item.toolTip = item.label
            item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            item.action = #selector(revealSelected)

        default:
            return nil
        }
        return item
    }

    /// 模板操作菜单：恢复被删除的内置模板 / 打开模板目录。
    private func makeTemplatesMenuToolbarItem(_ identifier: NSToolbarItem.Identifier) -> NSToolbarItem {
        let item = NSMenuToolbarItem(itemIdentifier: identifier)
        item.label = NSLocalizedString("console.toolbar.templates", comment: "")
        item.paletteLabel = item.label
        item.toolTip = item.label
        item.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: nil)
        item.isBordered = true
        item.showsIndicator = true

        let menu = NSMenu()
        let restore = NSMenuItem(title: NSLocalizedString("console.toolbar.restoreBuiltins", comment: ""),
                                 action: #selector(restoreBuiltins), keyEquivalent: "")
        restore.target = self
        restore.image = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: nil)
        menu.addItem(restore)

        let openFolder = NSMenuItem(title: NSLocalizedString("console.toolbar.revealFolder", comment: ""),
                                    action: #selector(revealTemplatesFolder), keyEquivalent: "")
        openFolder.target = self
        openFolder.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        menu.addItem(openFolder)

        item.menu = menu
        return item
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        if item.itemIdentifier == ToolbarID.edit {
            return detail.currentTemplate != nil
        }
        return true
    }
}
