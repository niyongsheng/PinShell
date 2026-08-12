import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// CLI 传入的 HTML（本进程宿主模式）
    var pendingFile: URL?

    private var statusItemController: StatusItemController!
    private var windowController: OverlayWindowController!
    /// openFiles 事件可能早于 applicationDidFinishLaunching 到达，先缓冲（只取第一个）
    private var queuedFile: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        windowController = OverlayWindowController()
        statusItemController = StatusItemController(windowController: windowController)

        // 加载优先级：openFiles 队列 > CLI 参数 > 上次打开路径 > 内置占位页
        var target = queuedFile.map(URL.init(fileURLWithPath:))
        queuedFile = nil
        if target == nil { target = pendingFile }
        if target == nil { target = AppState.lastHTMLURL }
        if target == nil { target = Bundle.main.url(forResource: "Placeholder", withExtension: "html") }

        if let url = target { windowController.loadHTML(url) }
        windowController.showWindow()
    }

    // MARK: - 文件打开事件（CLI / open -a 路由到这里）

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if let wc = windowController {
            if let first = filenames.first { wc.loadHTML(URL(fileURLWithPath: first)) }
        } else {
            queuedFile = filenames.first
        }
        sender.reply(toOpenOrPrint: .success)   // 必须回复，否则事件挂起
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false   // 菜单栏常驻应用，无主窗口
    }

}
