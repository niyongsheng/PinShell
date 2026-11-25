import AppKit
import PinShellCore

/// 状态栏菜单（spec 2.4）：程序唯一入口，无主应用窗口。
/// 保持 macOS 原生样式：logo 生成的 template 图标 + 原生 NSMenu。
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let windowController: OverlayWindowController
    /// 首次打开控制台时才构建（避免启动即建第二个 WKWebView + 扫描模板目录）
    private lazy var consoleController = ConsoleController(windowController: windowController)
    private var consoleItem: NSMenuItem!
    private var windowStateItem: NSMenuItem!
    private var visibilityItem: NSMenuItem!
    private var visibilityRow: MenuToggleRowView!
    private var statusMenu: NSMenu!
    private var positionItem: NSMenuItem!
    private var displayModeItems: [DisplayMode: NSMenuItem] = [:]
    private var isPresentingMenu = false
    /// NSStatusBarButton 不会把右键转成 action，单独监听状态栏窗口的右键。
    private var rightClickMonitor: Any?
    /// 下载安装包时惰性创建（只在主线程使用）
    private var updateInstaller: UpdateInstaller?
    private var installTask: Task<Void, Never>?

    init(windowController: OverlayWindowController) {
        self.windowController = windowController
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureItem()
        configureMenu()
        installRightClickMonitor()
        windowController.statusItemAnchorProvider = { [weak self] in
            self?.currentStatusItemAnchor
        }
        NotificationCenter.default.addObserver(self, selector: #selector(passthroughChanged(_:)),
                                               name: .pinshellPassthroughChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(shortcutsChanged),
                                               name: .pinshellShortcutsChanged, object: nil)
        // 全局快捷键：App 未激活时也能打开控制台 / 显隐悬浮窗 / 切换穿透。
        let dispatcher = ShortcutDispatcher.shared
        dispatcher.register(.openConsole) { [weak self] in self?.openConsole(nil) }
        dispatcher.register(.toggleOverlay) { [weak self] in self?.toggleVisibility(nil) }
        dispatcher.register(.togglePassthrough) { [weak self] in
            guard let self else { return }
            self.togglePassthrough(self.windowStateItem)
        }
        dispatcher.register(.toggleDisplayMode) { [weak self] in self?.toggleDisplayMode() }
        dispatcher.startGlobalHotKeys()
    }

    deinit {
        if let rightClickMonitor { NSEvent.removeMonitor(rightClickMonitor) }
        NotificationCenter.default.removeObserver(self)
    }

    private func configureItem() {
        // 菜单栏图标取自 Resources/logo.svg（make menubar-icon 生成黑色 template PNG）
        let image = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "PinShell")
        image?.isTemplate = true
        statusItem.button?.image = image

        // 菜单不再常驻挂载：左键在菜单栏模式下切换模板弹出，右键临时挂载菜单。
        // NSStatusBarButton 的 action 只走左键；右键由 installRightClickMonitor 接管。
        restoreButtonRouting()
        updateToolTip()
    }

    private func installRightClickMonitor() {
        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] event in
            guard let self,
                  self.statusItem.menu == nil,
                  let button = self.statusItem.button,
                  let window = button.window,
                  event.window === window else { return event }
            let point = button.convert(event.locationInWindow, from: nil)
            guard button.bounds.contains(point) else { return event }
            self.presentStatusMenu()
            return nil
        }
    }

    private func configureMenu() {
        let menu = NSMenu()
        // 关闭自动校验，否则 menuWillOpen 里设置的置灰状态会被 AppKit 按 target/action 重新启用
        menu.autoenablesItems = false

        let header = NSMenuItem(title: PinShellAppInfo.name, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        // 内容：控制台（快捷键由「快捷键」配置，见 updateShortcutTitles）
        consoleItem = NSMenuItem(title: NSLocalizedString("menu.console", comment: ""),
                                 action: #selector(openConsole(_:)), keyEquivalent: "")
        consoleItem.target = self
        menu.addItem(consoleItem)

        menu.addItem(.separator())

        // 显示方式：全局切换（桌面悬浮 / 菜单栏弹出）
        let displayModeRoot = NSMenuItem(title: NSLocalizedString("menu.displayMode", comment: ""),
                                         action: nil, keyEquivalent: "")
        let displayModeMenu = NSMenu()
        for mode in DisplayMode.allCases {
            let key = mode == .desktop ? "menu.displayMode.desktop" : "menu.displayMode.menuBar"
            let item = NSMenuItem(title: NSLocalizedString(key, comment: ""),
                                  action: #selector(selectDisplayMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            displayModeMenu.addItem(item)
            displayModeItems[mode] = item
        }
        displayModeRoot.submenu = displayModeMenu
        menu.addItem(displayModeRoot)

        // 位置：四角预设子菜单
        positionItem = NSMenuItem(title: NSLocalizedString("menu.position", comment: ""),
                                  action: nil, keyEquivalent: "")
        let positionMenu = NSMenu()
        let corners: [(corner: WindowAnchor, titleKey: String)] = [
            (.topLeft, "menu.position.topLeft"),
            (.topRight, "menu.position.topRight"),
            (.bottomLeft, "menu.position.bottomLeft"),
            (.bottomRight, "menu.position.bottomRight"),
        ]
        for entry in corners {
            let item = NSMenuItem(title: NSLocalizedString(entry.titleKey, comment: ""),
                                  action: #selector(moveToCorner(_:)),
                                  keyEquivalent: "")
            item.representedObject = entry.corner.rawValue
            item.target = self
            positionMenu.addItem(item)
        }
        positionItem.submenu = positionMenu
        menu.addItem(positionItem)

        // 窗口显隐：原生菜单没有开关控件，用自定义视图承载标题 + NSSwitch（开 = 显示）
        visibilityRow = MenuToggleRowView()
        visibilityRow.onChange = { [weak self] isOn in
            self?.setWindowVisibility(isOn)
        }
        visibilityItem = NSMenuItem(title: NSLocalizedString("menu.windowHidden", comment: ""),
                                    action: #selector(toggleVisibility(_:)), keyEquivalent: "")
        visibilityItem.target = self
        visibilityItem.view = visibilityRow
        menu.addItem(visibilityItem)

        // 窗口状态：交互 / 穿透（置于显隐开关下方）
        windowStateItem = NSMenuItem(title: "", action: #selector(togglePassthrough(_:)),
                                     keyEquivalent: "")
        windowStateItem.target = self
        menu.addItem(windowStateItem)

        menu.addItem(.separator())

        // 应用：更新检查 / 退出
        let checkUpdates = NSMenuItem(title: NSLocalizedString("menu.checkForUpdates", comment: ""),
                                      action: #selector(checkForUpdates(_:)), keyEquivalent: "u")
        checkUpdates.target = self
        menu.addItem(checkUpdates)

        let quit = NSMenuItem(title: NSLocalizedString("menu.quit", comment: ""),
                              action: #selector(quit(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        menu.delegate = self
        statusMenu = menu
        refreshMenuState()
    }

    /// 每次展开菜单时兜底刷新各项状态（外部路径直接 orderOut 时也能保持一致）
    func menuWillOpen(_ menu: NSMenu) {
        refreshMenuState()
    }

    /// 菜单项状态的唯一刷新入口：构建、展开、切换显示方式后共用。
    private func refreshMenuState() {
        updateDisplayModeItems()
        updateWindowStateItem(windowStateItem)
        updateMenuAvailability()
        updateShortcutTitles()
        updateToolTip()
    }

    /// 快捷键只写进标题做展示：菜单 keyEquivalent 会与 Carbon 热键重复触发。
    private func updateShortcutTitles() {
        consoleItem.title = menuTitle("menu.console", shortcut: .openConsole)
    }

    private func menuTitle(_ key: String, shortcut action: ShortcutAction) -> String {
        let base = NSLocalizedString(key, comment: "")
        guard let combo = ShortcutStore.shared.combo(for: action) else { return base }
        return "\(base)  \(combo.displayString)"
    }

    @objc private func shortcutsChanged() {
        refreshMenuState()
    }

    func menuDidClose(_ menu: NSMenu) {
        if statusItem.menu === statusMenu {
            statusItem.menu = nil
        }
        restoreButtonRouting()
    }

    // MARK: - 状态栏点击路由

    @objc private func statusItemClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        let isSecondary = event?.type == .rightMouseUp
            || event?.type == .rightMouseDown
            || (event?.modifierFlags.contains(.control) ?? false)

        if isSecondary {
            presentStatusMenu()
            return
        }

        // 菜单栏模式且已有真实模板（或面板已弹出）：左键切换弹出；
        // 否则保持原有菜单入口，保证首启/空库时也能进控制台。
        if windowController.displayMode == .menuBar,
           windowController.hasUserContent || windowController.isWindowVisible {
            windowController.toggleVisibility()
            updateVisibilityItem()
        } else {
            presentStatusMenu()
        }
    }

    /// 临时挂载菜单再模拟点击：按钮挂着 menu 时 action 不会触发。
    /// 菜单（popUpMenu 层级）会盖在弹出面板之上；面板保留，切换显示方式后可直接迁移。
    private func presentStatusMenu() {
        guard !isPresentingMenu else { return }
        isPresentingMenu = true
        statusItem.menu = statusMenu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
        isPresentingMenu = false
        restoreButtonRouting()
    }

    /// 摘掉菜单后重新声明 button 路由（AppKit 可能重配 button）。
    private func restoreButtonRouting() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        _ = button.sendAction(on: [.leftMouseUp])
    }

    /// 状态栏按钮在屏幕坐标中的位置 + 所在屏幕的可见区域。
    private var currentStatusItemAnchor: StatusItemAnchor? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        let icon = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = NSScreen.screens.first { $0.frame.intersects(icon) }
            ?? window.screen ?? NSScreen.main
        guard let screen else { return nil }
        return StatusItemAnchor(
            iconFrame: WindowFrame(icon),
            visibleFrame: WindowFrame(screen.visibleFrame))
    }

    // MARK: - 显示方式

    private func toggleDisplayMode() {
        let next: DisplayMode = windowController.displayMode == .desktop ? .menuBar : .desktop
        windowController.setDisplayMode(next)
        refreshMenuState()
    }

    @objc private func selectDisplayMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = DisplayMode(rawValue: raw) else { return }
        windowController.setDisplayMode(mode)
        refreshMenuState()
    }

    private func updateDisplayModeItems() {
        for (mode, item) in displayModeItems {
            item.state = windowController.displayMode == mode ? .on : .off
        }
    }

    /// 菜单栏模式下位置/穿透/窗口显隐都由菜单栏图标接管，菜单项置灰。
    private func updateMenuAvailability() {
        let isDesktop = windowController.displayMode == .desktop
        positionItem?.isEnabled = isDesktop
        windowStateItem?.isEnabled = isDesktop
        updateVisibilityItem()
    }

    private func updateToolTip() {
        let key = windowController.displayMode == .desktop
            ? "menu.tooltip.desktop" : "menu.tooltip.menuBar"
        statusItem.button?.toolTip = NSLocalizedString(key, comment: "")
    }

    private func updateWindowStateItem(_ item: NSMenuItem) {
        item.title = menuTitle(
            windowController.effectivePassthroughEnabled
                ? "menu.windowState.passthrough"
                : "menu.windowState.interactive",
            shortcut: .togglePassthrough)
    }

    private func updateVisibilityItem() {
        guard let item = visibilityItem else { return }
        let visible = windowController.isWindowVisible
        let key = visible ? "menu.windowShown" : "menu.windowHidden"
        item.title = NSLocalizedString(key, comment: "")   // 供辅助功能读取；勾选态由开关视图表达
        item.isEnabled = windowController.displayMode == .desktop
            && (visible || windowController.currentURL != nil)
        visibilityRow.title = menuTitle(key, shortcut: .toggleOverlay)
        visibilityRow.isOn = visible
        visibilityRow.isRowEnabled = item.isEnabled
    }

    /// 供 PINSHELL_SHOW_CONSOLE=1 启动时直接打开控制台（也用于自动化截图）。
    func showConsole() {
        openConsole(nil)
    }

    /// 官网深链：打开控制台与模板库，并安装指定模板。
    func installTemplateFromLibrary(id: String, catalogURL: URL) {
        windowController.dismissMenuBarPopover()
        consoleController.installTemplateFromLibrary(id: id, catalogURL: catalogURL)
    }

    @objc private func openConsole(_ sender: Any?) {
        windowController.dismissMenuBarPopover()
        consoleController.show()
    }
    @objc private func passthroughChanged(_ notification: Notification) {
        updateWindowStateItem(windowStateItem)   // 控制台开关联动菜单项
    }

    @objc private func toggleVisibility(_ sender: Any?) {
        windowController.toggleVisibility()
        updateVisibilityItem()
    }

    /// 开关的目标态与当前态不一致时才切换，避免重复点击时来回抖动。
    private func setWindowVisibility(_ visible: Bool) {
        guard visible != windowController.isWindowVisible else {
            updateVisibilityItem()
            return
        }
        windowController.toggleVisibility()
        updateVisibilityItem()
    }

    @objc private func togglePassthrough(_ sender: NSMenuItem) {
        windowController.togglePassthrough()
        updateWindowStateItem(sender)
    }

    @objc private func moveToCorner(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let corner = WindowAnchor(rawValue: raw) else { return }
        windowController.moveToCorner(corner)
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    // MARK: - 更新检查

    /// 启动后静默自动检查：距上次检查超过 checkInterval 才查，延迟 autoCheckDelay 不打断首次使用
    func scheduleAutomaticUpdateCheck() {
        if let last = AppState.lastUpdateCheckDate,
           Date().timeIntervalSince(last) < UpdateChecker.checkInterval {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + UpdateChecker.autoCheckDelay) { [weak self] in
            self?.performCheck(automatic: true)
        }
    }

    private var isChecking = false

    @objc private func checkForUpdates(_ sender: Any?) {
        performCheck(automatic: false)
    }

    private func performCheck(automatic: Bool) {
        // 已有检查在进行或正在下载安装包，忽略重复触发
        guard !isChecking, installTask == nil else { return }
        isChecking = true
        Task { @MainActor in
            let result = await UpdateChecker.check()
            isChecking = false
            AppState.lastUpdateCheckDate = Date()
            switch result {
            case .upToDate:
                // 自动检查静默；手动检查才提示"已是最新"
                if !automatic {
                    showMessageAlert(title: NSLocalizedString("update.upToDate", comment: ""),
                                     message: String(format: NSLocalizedString("update.upToDateMessage", comment: ""),
                                                    UpdateChecker.currentVersion))
                }
            case .updateAvailable(let release):
                showUpdateAlert(release)
            case .failed(let message):
                // 自动检查失败静默（国内访问 GitHub 可能不稳，不打扰用户）
                if !automatic {
                    showMessageAlert(title: NSLocalizedString("update.checkFailed", comment: ""),
                                     message: String(format: NSLocalizedString("update.checkFailedMessage", comment: ""),
                                                    message))
                }
            }
        }
    }

    private func showUpdateAlert(_ release: UpdateChecker.ReleaseInfo) {
        windowController.dismissMenuBarPopover()   // 状态栏层级面板会盖住模态弹窗
        let alert = NSAlert()
        alert.messageText = String(format: NSLocalizedString("update.availableTitle", comment: ""), release.versionLabel)
        // Release 说明按 Markdown 渲染，长文在固定高度内滚动；安装提示放在内容区底部。
        let notes = (release.body ?? release.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = String(format: NSLocalizedString("update.availableMessage", comment: ""),
                              release.versionLabel)
        alert.accessoryView = UpdateAlertContent.make(markdown: notes.isEmpty ? fallback : notes)
        alert.addButton(withTitle: NSLocalizedString("update.download", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("update.later", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("update.skip", comment: ""))
        let response = alert.runAppModal()
        if response == .alertFirstButtonReturn {
            if release.pkgAsset != nil {
                startInstall(release)
            } else {
                // 旧版本发布没有 pkg，退化为打开发布页手动下载
                showMessageAlert(title: NSLocalizedString("update.packageUnavailableTitle", comment: ""),
                                 message: NSLocalizedString("update.packageUnavailable", comment: ""))
                NSWorkspace.shared.open(release.htmlURL ?? UpdateChecker.releasesPageURL)
            }
        } else if response == .alertThirdButtonReturn {
            AppState.skippedVersion = release.versionLabel   // 该版本不再提醒
        }
    }

    // MARK: - 下载安装包

    private func startInstall(_ release: UpdateChecker.ReleaseInfo) {
        guard installTask == nil else { return }
        installTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let installer = self.updateInstaller ?? UpdateInstaller()
            self.updateInstaller = installer

            let result: Result<Void, Error>
            do {
                try await installer.install(release)
                result = .success(())
            } catch {
                result = .failure(error)
            }

            // 先清空任务，错误弹窗里的「重试」才能再次进入
            self.installTask = nil
            if case .failure(let error) = result, !(error is CancellationError) {
                self.showInstallError(error, release: release)
            }
        }
    }

    private func showInstallError(_ error: Error, release: UpdateChecker.ReleaseInfo) {
        windowController.dismissMenuBarPopover()
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("update.installFailed", comment: "")
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: NSLocalizedString("update.retry", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("update.openReleasePage", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("update.cancel", comment: ""))

        switch alert.runAppModal() {
        case .alertFirstButtonReturn:
            startInstall(release)
        case .alertSecondButtonReturn:
            NSWorkspace.shared.open(release.htmlURL ?? UpdateChecker.releasesPageURL)
        default:
            break
        }
    }

    private func showMessageAlert(title: String, message: String) {
        windowController.dismissMenuBarPopover()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: NSLocalizedString("console.error.ok", comment: ""))
        alert.runAppModal()
    }
}
