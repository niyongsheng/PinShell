/// 单个 CLI 子命令的说明：`--help` 与控制台「CLI」页共用。
struct CLICommandSpec {
    /// `--help` 中 `PinShell` 之后的用法片段。
    let usage: String
    let summary: String
    /// 控制台展示的示例与说明；nil 表示不在控制台展示。
    let consoleExample: String?
    let consoleDescriptionKey: String?
}

/// CLI 命令清单：帮助文本、控制台速查与 `mcp` 特判都从这里读取。
enum CLICommandCatalog {
    static let mcpName = "mcp"

    static let commands: [CLICommandSpec] = [
        CLICommandSpec(usage: "[show] <file> [options]",
                       summary: "Show a local HTML file",
                       consoleExample: "PinShell show ./panel.html --watch",
                       consoleDescriptionKey: "console.cli.command.show"),
        CLICommandSpec(usage: "set [options]",
                       summary: "Update the current overlay",
                       consoleExample: "PinShell set --size 320x120 --position bottom-right",
                       consoleDescriptionKey: "console.cli.command.set"),
        CLICommandSpec(usage: "reload",
                       summary: "Reload the current file",
                       consoleExample: "PinShell reload",
                       consoleDescriptionKey: "console.cli.command.reload"),
        CLICommandSpec(usage: "eval <js> [--json]",
                       summary: "Evaluate JS in the page",
                       consoleExample: "PinShell eval 'document.title' --json",
                       consoleDescriptionKey: "console.cli.command.eval"),
        CLICommandSpec(usage: "emit <event> [json]",
                       summary: "Dispatch an event to the page",
                       consoleExample: "PinShell emit agent:message '{\"text\":\"next\"}'",
                       consoleDescriptionKey: "console.cli.command.emit"),
        CLICommandSpec(usage: "listen [--json]",
                       summary: "Stream page events (agent)",
                       consoleExample: "PinShell listen --json",
                       consoleDescriptionKey: "console.cli.command.listen"),
        CLICommandSpec(usage: "status [--json]",
                       summary: "Print overlay state",
                       consoleExample: "PinShell status --json",
                       consoleDescriptionKey: "console.cli.command.status"),
        CLICommandSpec(usage: "templates [--json]",
                       summary: "List auto-discovered templates",
                       consoleExample: "PinShell templates --json",
                       consoleDescriptionKey: "console.cli.command.templates"),
        CLICommandSpec(usage: "close",
                       summary: "Hide the overlay",
                       consoleExample: "PinShell close",
                       consoleDescriptionKey: "console.cli.command.close"),
        CLICommandSpec(usage: "quit",
                       summary: "Quit PinShell",
                       consoleExample: "PinShell quit",
                       consoleDescriptionKey: "console.cli.command.quit"),
        CLICommandSpec(usage: mcpName,
                       summary: "Run the MCP 2.0 stdio server (agent)",
                       consoleExample: "PinShell \(mcpName)",
                       consoleDescriptionKey: "console.cli.command.mcp"),
    ]
}
