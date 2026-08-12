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
}
