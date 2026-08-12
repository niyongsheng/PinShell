import AppKit
import Darwin

// 关闭 stdout 缓冲：CLI 模式调试友好
setvbuf(stdout, nil, _IONBF, 0)

// PinShell 入口：PinShell [path/to/file.html]
// - 传入文件时，交接给 LaunchServices：App 已运行则路由到 application(_:openFiles:)，
//   未运行则拉起新实例，本 CLI 进程随即退出；
// - 交接失败（未注册的裸二进制开发模式）：本进程直接成为宿主，路径作为 pendingFile。
let pendingFile: URL?
if CommandLine.arguments.count > 1 {
    let arg = CommandLine.arguments[1]
    if arg == "--help" || arg == "-h" {
        print("PinShell — 将本地 HTML 渲染为全局置顶、可点击穿透的悬浮窗")
        print("用法: PinShell [path/to/file.html]")
        exit(0)
    }
    // 基于调用进程 cwd 解析为绝对路径 —— 绝不能把相对路径交给另一进程
    let url = URL(fileURLWithPath: arg).standardizedFileURL
    if url.isRegularFile {
        pendingFile = url
    } else {
        FileHandle.standardError.write(Data("PinShell: 文件不存在或不是普通文件: \(arg)\n".utf8))
        exit(1)
    }
} else {
    pendingFile = nil
}

if let file = pendingFile {
    // 交接给 LaunchServices：已运行则路由到 openFiles，未运行则拉起，本进程等待结果后退出。
    // 失败（App 未注册）则本进程直接成为宿主。
    // 目标 App URL：自身在 .app 内直接用 bundle；裸二进制则按 bundleID 查已注册应用
    var appURL = Bundle.main.bundleURL
    if appURL.pathExtension != "app" {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.pinshell.app"
        if let found = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            appURL = found
        }
    }
    let config = NSWorkspace.OpenConfiguration()
    let sem = DispatchSemaphore(value: 0)
    var handedOff = false
    NSWorkspace.shared.open([file], withApplicationAt: appURL,
                            configuration: config) { _, error in
        handedOff = (error == nil)
        sem.signal()
    }
    sem.wait()
    if handedOff { exit(0) }   // 交接成功：目标 App 处理文件，本进程退出
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // LSUIElement 冗余但无害；裸二进制开发模式下必需

let delegate = AppDelegate()
delegate.pendingFile = pendingFile
app.delegate = delegate
app.run()
