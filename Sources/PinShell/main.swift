import AppKit
import Darwin

// 关闭 stdout 缓冲：CLI 输出与 listen 事件即时可见
setvbuf(stdout, nil, _IONBF, 0)

// PinShell 双模式：
// - 有子命令/文件参数 → CLI 客户端（必要时拉起 App），执行完退出；
// - 无参数 → App 宿主模式，常驻菜单栏并监听控制 socket。
let arguments = Array(CommandLine.arguments.dropFirst())

// MCP 2.0 stdio server：供 Claude Code 等 MCP 客户端以子进程方式拉起
if arguments.first == "mcp" {
    if arguments.contains("--help") {
        MCPServer.printHelp()
        exit(0)
    }
    let server = MCPServer()   // 具名绑定保证 stdio 循环期间 server 存活（队列任务弱引用它）
    exit(server.run())
}

if let command = CLICommand.parse(arguments) {
    exit(CLICommand.run(command))
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)   // LSUIElement 冗余但无害；裸二进制开发模式下必需

    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
