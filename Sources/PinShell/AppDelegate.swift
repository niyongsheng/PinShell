import AppKit
import Darwin
import PinShellCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController!
    private var windowController: OverlayWindowController!
    private var controlServer: ControlServer?
    private var controlHost: ControlHost?
    /// openFiles 事件可能早于 applicationDidFinishLaunching 到达，先缓冲（只取第一个）
    private var queuedFile: String?
    /// 官网深链可能早于启动完成到达，先缓冲。
    private var queuedDeepLink: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 自动化截图时可用 PINSHELL_APPEARANCE=dark 强制深色，不需要改系统外观
        if ProcessInfo.processInfo.environment["PINSHELL_APPEARANCE"] == "dark" {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        SharedTemplateAssets.seedOnce()
        // 空模板目录（首次安装）先播种内置工作日历，画廊不可达时也有可用内容。
        let bundledTemplate = BundledTemplates.seedIfNeeded()
        // 首次安装使用菜单栏弹出作为默认展示方式；用户已选过则不覆盖。
        if bundledTemplate != nil, !AppState.hasDisplayModePreference {
            AppState.displayMode = .menuBar
        }
        windowController = OverlayWindowController()
        statusItemController = StatusItemController(windowController: windowController)

        // 单实例锁 = 控制 socket。第二个实例激活已有 App 后退出。
        let server = ControlServer()
        if server.start() {
            controlServer = server
            controlHost = ControlHost(windowController: windowController, server: server)
        } else {
            activateOtherInstance()
            NSApp.terminate(nil)
            return
        }

        Analytics.shared.trackLaunchIfNeeded()                 // 匿名统计：仅上报启动事件
        statusItemController.scheduleAutomaticUpdateCheck()   // 启动 5s 后静默检查更新（24h 节流）

        // 加载优先级：openFiles 队列 > 上次打开的有效模板 > 内置模板 > 内置占位页
        let queued = queuedFile.map(URL.init(fileURLWithPath:))
        queuedFile = nil
        let lastTemplate = AppState.lastHTMLURL.flatMap { url -> URL? in
            // 占位页只是首启兜底，不算“用户已选模板”
            guard !OverlayWindowController.isPlaceholder(url) else { return nil }
            return url.isRegularFile ? url : nil
        }
        let target = queued ?? lastTemplate ?? bundledTemplate
            ?? OverlayWindowController.placeholderURL

        if let url = target {
            // 菜单栏弹出模式启动时只恢复内容，等用户点击图标再展示；
            // openFiles 队列属于用户显式打开，仍然直接展示。
            let present = queued != nil || windowController.displayMode == .desktop
            windowController.loadHTML(url, present: present)
        } else if windowController.displayMode == .desktop {
            windowController.showWindow()
        }

        // PINSHELL_SHOW_CONSOLE=1：启动后直接打开控制台，方便脚本/自动化截图
        if ProcessInfo.processInfo.environment["PINSHELL_SHOW_CONSOLE"] == "1" {
            DispatchQueue.main.async { [weak self] in
                self?.statusItemController.showConsole()
            }
        }

        if let url = queuedDeepLink {
            queuedDeepLink = nil
            handleDeepLink(url)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controlServer?.stop()
    }

    // MARK: - 文件打开事件（open -a / Finder 路由到这里）

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if let wc = windowController {
            if let first = filenames.first {
                wc.setWatching(false)   // Finder/open -a 等同于不带 --watch 的 show
                wc.loadHTML(URL(fileURLWithPath: first))
            }
        } else {
            queuedFile = filenames.first
        }
        sender.reply(toOpenOrPrint: .success)   // 必须回复，否则事件挂起
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false   // 菜单栏常驻应用，无主窗口
    }

    // MARK: - 官网深链

    func application(_ application: NSApplication, open urls: [URL]) {
        // 实现 open(_:) 后，Finder/open -a 的文件 URL 也会走这里。
        let filePaths = urls.filter(\.isFileURL).map(\.path)
        if !filePaths.isEmpty {
            self.application(application, openFiles: filePaths)
        }

        guard let url = urls.first(where: { $0.scheme?.lowercased() == PinShellDeepLink.scheme })
        else { return }
        if statusItemController == nil {
            queuedDeepLink = url
        } else {
            handleDeepLink(url)
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard let request = PinShellDeepLink.installRequest(
            from: url,
            trustedCatalogURL: TemplateLibraryPreferences.catalogURL()
        ) else {
            NSLog("PinShell: ignored untrusted deep link %@", url.absoluteString)
            return
        }
        statusItemController.installTemplateFromLibrary(id: request.templateID)
    }

    // MARK: - 单实例

    private func activateOtherInstance() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == bundleID && $0.processIdentifier != getpid() }?
            .activate(options: [])
    }
}
