import AppKit
import UniformTypeIdentifiers

/// 状态栏菜单（spec 2.4）：程序唯一入口，无主应用窗口。
/// 保持 macOS 原生样式：logo 生成的 template 图标 + 原生 NSMenu。
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let windowController: OverlayWindowController
    /// 首次打开模板库时才构建（避免启动即建第二个 WKWebView + 读 manifest）
    private lazy var galleryController = TemplateGalleryController(windowController: windowController)
    private var passthroughItem: NSMenuItem!

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

        let gallery = NSMenuItem(title: NSLocalizedString("menu.templates", comment: ""),
                                 action: #selector(openGallery(_:)), keyEquivalent: "l")
        gallery.target = self
        menu.addItem(gallery)

        let open = NSMenuItem(title: NSLocalizedString("menu.chooseHTML", comment: ""),
                              action: #selector(chooseHTML(_:)), keyEquivalent: "o")
        open.target = self
        menu.addItem(open)

        passthroughItem = NSMenuItem(title: "", action: #selector(togglePassthrough(_:)), keyEquivalent: "t")
        passthroughItem.target = self
        menu.addItem(passthroughItem)
        updatePassthroughItem(passthroughItem)

        let reset = NSMenuItem(title: NSLocalizedString("menu.resetPosition", comment: ""),
                               action: #selector(resetPosition(_:)), keyEquivalent: "0")
        reset.target = self
        menu.addItem(reset)

        let reload = NSMenuItem(title: NSLocalizedString("menu.reloadHTML", comment: ""),
                                action: #selector(reloadHTML(_:)), keyEquivalent: "r")
        reload.target = self
        menu.addItem(reload)

        let checkUpdates = NSMenuItem(title: NSLocalizedString("menu.checkForUpdates", comment: ""),
                                      action: #selector(checkForUpdates(_:)), keyEquivalent: "u")
        checkUpdates.target = self
        menu.addItem(checkUpdates)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: NSLocalizedString("menu.quit", comment: ""),
                              action: #selector(quit(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func updatePassthroughItem(_ item: NSMenuItem) {
        let enabled = AppState.passthroughEnabled
        item.state = enabled ? .on : .off
        item.title = enabled
            ? NSLocalizedString("menu.passthrough.on", comment: "")
            : NSLocalizedString("menu.passthrough.off", comment: "")
    }

    @objc private func openGallery(_ sender: Any?) {
        galleryController.show()
    }
    @objc private func passthroughChanged(_ notification: Notification) {
        updatePassthroughItem(passthroughItem)   // 模板库开关联动菜单项
    }

    @objc private func chooseHTML(_ sender: Any?) {
        let openPanel = NSOpenPanel()
        openPanel.title = NSLocalizedString("openPanel.title", comment: "")
        openPanel.prompt = NSLocalizedString("openPanel.prompt", comment: "")
        var types: [UTType] = [.html]
        if let htm = UTType(filenameExtension: "htm") { types.append(htm) }
        openPanel.allowedContentTypes = types
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)   // accessory 应用下可能被忽略（设计风险 R3）
        guard openPanel.runModal() == .OK, let url = openPanel.url else { return }
        windowController.loadHTML(url)
    }

    @objc private func togglePassthrough(_ sender: NSMenuItem) {
        windowController.togglePassthrough()
        updatePassthroughItem(sender)
    }

    @objc private func resetPosition(_ sender: Any?) {
        windowController.resetToDefaultFrame()
    }

    @objc private func reloadHTML(_ sender: Any?) {
        windowController.reloadHTML()
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    // MARK: - 更新检查

    /// 启动后静默自动检查：距上次检查超过 24h 才查，延迟 5s 不打断首次使用
    func scheduleAutomaticUpdateCheck() {
        if let last = AppState.lastUpdateCheckDate, Date().timeIntervalSince(last) < 24 * 3600 {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.performCheck(automatic: true)
        }
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        performCheck(automatic: false)
    }

    private func performCheck(automatic: Bool) {
        Task { @MainActor in
            let result = await UpdateChecker.check()
            AppState.lastUpdateCheckDate = Date()
            switch result {
            case .upToDate:
                // 自动检查静默；手动检查才提示"已是最新"
                if !automatic { showUpToDateAlert() }
            case .updateAvailable(let release):
                showUpdateAlert(release)
            case .failed(let message):
                // 自动检查失败静默（国内访问 GitHub 可能不稳，不打扰用户）
                if !automatic { showCheckFailedAlert(message) }
            }
        }
    }

    private func showUpdateAlert(_ release: UpdateChecker.ReleaseInfo) {
        NSApp.activate(ignoringOtherApps: true)   // accessory 应用下弹窗需先激活
        let alert = NSAlert()
        alert.messageText = String(format: NSLocalizedString("update.availableTitle", comment: ""), release.versionLabel)
        alert.informativeText = releaseNotesExcerpt(release)
        alert.addButton(withTitle: NSLocalizedString("update.download", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("update.later", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("update.skip", comment: ""))
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.htmlURL ?? UpdateChecker.releasesPageURL)
        } else if response == .alertThirdButtonReturn {
            AppState.skippedVersion = release.versionLabel   // 该版本不再提醒
        }
    }

    /// release 说明摘录：优先 GitHub 的 name，body 截断到 500 字
    private func releaseNotesExcerpt(_ release: UpdateChecker.ReleaseInfo) -> String {
        if let name = release.name, !name.isEmpty { return name }
        guard let body = release.body else {
            return String(format: NSLocalizedString("update.availableMessage", comment: ""), release.versionLabel)
        }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 500 ? String(trimmed.prefix(500)) + "…" : trimmed
    }

    private func showUpToDateAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("update.upToDate", comment: "")
        alert.informativeText = String(format: NSLocalizedString("update.upToDateMessage", comment: ""),
                                       UpdateChecker.currentVersion)
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showCheckFailedAlert(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("update.checkFailed", comment: "")
        alert.informativeText = String(format: NSLocalizedString("update.checkFailedMessage", comment: ""), message)
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
