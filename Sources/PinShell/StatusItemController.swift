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
    private var passthroughOpacityLabel: NSTextField!

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

        // 内容：模板库 / 选文件 / 重载
        let gallery = NSMenuItem(title: NSLocalizedString("menu.templates", comment: ""),
                                 action: #selector(openGallery(_:)), keyEquivalent: "l")
        gallery.target = self
        menu.addItem(gallery)

        let open = NSMenuItem(title: NSLocalizedString("menu.chooseHTML", comment: ""),
                              action: #selector(chooseHTML(_:)), keyEquivalent: "o")
        open.target = self
        menu.addItem(open)

        let reload = NSMenuItem(title: NSLocalizedString("menu.reloadHTML", comment: ""),
                                action: #selector(reloadHTML(_:)), keyEquivalent: "r")
        reload.target = self
        menu.addItem(reload)

        menu.addItem(.separator())

        // 穿透：位置复位 / 开关 / 透明度滑块
        let reset = NSMenuItem(title: NSLocalizedString("menu.resetPosition", comment: ""),
                               action: #selector(resetPosition(_:)), keyEquivalent: "0")
        reset.target = self
        menu.addItem(reset)

        passthroughItem = NSMenuItem(title: "", action: #selector(togglePassthrough(_:)), keyEquivalent: "t")
        passthroughItem.target = self
        menu.addItem(passthroughItem)
        updatePassthroughItem(passthroughItem)
        menu.addItem(makePassthroughOpacityItem())

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

        statusItem.menu = menu
    }

    private func updatePassthroughItem(_ item: NSMenuItem) {
        let enabled = AppState.passthroughEnabled
        item.state = enabled ? .on : .off
        item.title = enabled
            ? NSLocalizedString("menu.passthrough.on", comment: "")
            : NSLocalizedString("menu.passthrough.off", comment: "")
    }

    /// 穿透透明度滑块（0.3~1.0）：拖动实时注入 CSS 变量，穿透开关状态不受影响
    private func makePassthroughOpacityItem() -> NSMenuItem {
        let item = NSMenuItem()
        // 约束布局：label 固有宽度 + slider 吃掉剩余，本地化文案长短都不错位
        let container = NSStackView()
        container.orientation = .horizontal
        container.alignment = .centerY
        container.spacing = 10
        container.edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
        container.frame = NSRect(x: 0, y: 0, width: 240, height: 30)
        container.translatesAutoresizingMaskIntoConstraints = false

        let opacity = AppState.passthroughOpacity
        let label = NSTextField(labelWithString: Self.opacityLabelText(opacity))
        label.font = .menuFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        passthroughOpacityLabel = label

        let slider = NSSlider(value: opacity, minValue: 0.3, maxValue: 1.0,
                              target: self, action: #selector(changePassthroughOpacity(_:)))
        slider.isContinuous = true
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)

        container.addArrangedSubview(label)
        container.addArrangedSubview(slider)
        item.view = container
        return item
    }

    private static func opacityLabelText(_ opacity: Double) -> String {
        String(format: NSLocalizedString("menu.passthroughOpacity", comment: ""),
               Int((opacity * 100).rounded()))
    }

    @objc private func changePassthroughOpacity(_ sender: NSSlider) {
        windowController.setPassthroughOpacity(sender.doubleValue)
        passthroughOpacityLabel.stringValue = Self.opacityLabelText(sender.doubleValue)
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
        guard !isChecking else { return }   // 已有检查在进行，忽略重复触发
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
        alert.informativeText = release.excerpt()
        alert.addButton(withTitle: NSLocalizedString("update.download", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("update.later", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("update.skip", comment: ""))
        let response = alert.runAppModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.htmlURL ?? UpdateChecker.releasesPageURL)
        } else if response == .alertThirdButtonReturn {
            AppState.skippedVersion = release.versionLabel   // 该版本不再提醒
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

private extension NSAlert {
    /// accessory 应用弹模态框前必须先激活，否则窗口不出现（设计风险 R3）
    @discardableResult
    func runAppModal() -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        return runModal()
    }
}
