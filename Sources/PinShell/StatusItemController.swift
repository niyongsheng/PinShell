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
    private var windowStateItem: NSMenuItem!
    private var visibilityItem: NSMenuItem!
    /// 下载安装包时惰性创建（只在主线程使用）
    private var updateInstaller: UpdateInstaller?
    private var installTask: Task<Void, Never>?

    init(windowController: OverlayWindowController) {
        self.windowController = windowController
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureItem()
        configureMenu()
        NotificationCenter.default.addObserver(self, selector: #selector(passthroughChanged(_:)),
                                               name: .pinshellPassthroughChanged, object: nil)
    }

    private func configureItem() {
        // 菜单栏图标取自 Resources/logo.svg（make menubar-icon 生成黑色 template PNG）
        let image = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "PinShell")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = "PinShell"
    }

    private func configureMenu() {
        let menu = NSMenu()

        let header = NSMenuItem(title: "PinShell", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        // 内容：控制台
        let console = NSMenuItem(title: NSLocalizedString("menu.console", comment: ""),
                                 action: #selector(openConsole(_:)), keyEquivalent: "k")
        console.target = self
        menu.addItem(console)

        menu.addItem(.separator())

        // 位置：四角预设子菜单；窗口状态：交互 / 穿透
        let position = NSMenuItem(title: NSLocalizedString("menu.position", comment: ""),
                                  action: nil, keyEquivalent: "")
        let positionMenu = NSMenu()
        let corners: [(corner: WindowAnchor, titleKey: String, shortcut: String)] = [
            (.topLeft, "menu.position.topLeft", ""),
            (.topRight, "menu.position.topRight", ""),
            (.bottomLeft, "menu.position.bottomLeft", ""),
            (.bottomRight, "menu.position.bottomRight", "0"),   // 沿用原 ⌘0 复位快捷键
        ]
        for entry in corners {
            let item = NSMenuItem(title: NSLocalizedString(entry.titleKey, comment: ""),
                                  action: #selector(moveToCorner(_:)),
                                  keyEquivalent: entry.shortcut)
            item.representedObject = entry.corner.rawValue
            item.target = self
            positionMenu.addItem(item)
        }
        position.submenu = positionMenu
        menu.addItem(position)

        windowStateItem = NSMenuItem(title: "", action: #selector(togglePassthrough(_:)), keyEquivalent: "t")
        windowStateItem.target = self
        menu.addItem(windowStateItem)
        updateWindowStateItem(windowStateItem)

        // 窗口显隐：开关项（勾选 = 显示），紧跟在窗口状态下方
        visibilityItem = NSMenuItem(title: NSLocalizedString("menu.showWindow", comment: ""),
                                    action: #selector(toggleVisibility(_:)), keyEquivalent: "h")
        visibilityItem.target = self
        menu.addItem(visibilityItem)
        updateVisibilityItem()

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
        statusItem.menu = menu
    }

    /// 每次展开菜单时兜底刷新显隐开关（外部路径直接 orderOut 时也能保持一致）
    func menuWillOpen(_ menu: NSMenu) {
        updateVisibilityItem()
    }

    private func updateWindowStateItem(_ item: NSMenuItem) {
        item.title = AppState.passthroughEnabled
            ? NSLocalizedString("menu.windowState.passthrough", comment: "")
            : NSLocalizedString("menu.windowState.interactive", comment: "")
    }

    private func updateVisibilityItem() {
        guard let item = visibilityItem else { return }
        let visible = windowController.isWindowVisible
        item.state = visible ? .on : .off
        item.isEnabled = visible || windowController.currentURL != nil
    }

    @objc private func openConsole(_ sender: Any?) {
        consoleController.show()
    }
    @objc private func passthroughChanged(_ notification: Notification) {
        updateWindowStateItem(windowStateItem)   // 控制台开关联动菜单项
    }

    @objc private func toggleVisibility(_ sender: Any?) {
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
        let alert = NSAlert()
        alert.messageText = String(format: NSLocalizedString("update.availableTitle", comment: ""), release.versionLabel)
        alert.informativeText = release.excerpt() + "\n\n" + NSLocalizedString("update.installHint", comment: "")
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
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runAppModal()
    }
}
