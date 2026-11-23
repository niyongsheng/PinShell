import AppKit
import Darwin

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController!
    private var windowController: OverlayWindowController!
    private var controlServer: ControlServer?
    private var controlHost: ControlHost?
    /// openFiles 事件可能早于 applicationDidFinishLaunching 到达，先缓冲（只取第一个）
    private var queuedFile: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 自动化截图时可用 PINSHELL_APPEARANCE=dark 强制深色，不需要改系统外观
        if ProcessInfo.processInfo.environment["PINSHELL_APPEARANCE"] == "dark" {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        SharedTemplateAssets.seedOnce()
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

        statusItemController.scheduleAutomaticUpdateCheck()   // 启动 5s 后静默检查更新（24h 节流）

        // 加载优先级：openFiles 队列 > 上次打开路径 > 内置占位页
        let queued = queuedFile.map(URL.init(fileURLWithPath:))
        queuedFile = nil
        let target = queued
            ?? AppState.lastHTMLURL
            ?? Bundle.main.url(forResource: "Placeholder", withExtension: "html")

        if let url = target { windowController.loadHTML(url) }
        windowController.showWindow()

        // PINSHELL_SHOW_CONSOLE=1：启动后直接打开控制台，方便脚本/自动化截图
        if ProcessInfo.processInfo.environment["PINSHELL_SHOW_CONSOLE"] == "1" {
            DispatchQueue.main.async { [weak self] in
                self?.statusItemController.showConsole()
            }
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

    // MARK: - 单实例

    private func activateOtherInstance() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == bundleID && $0.processIdentifier != getpid() }?
            .activate(options: [])
    }
}
