import AppKit

/// 控制台服务页面：侧边栏、详情页与快捷键共用同一套目的地。
enum ConsolePage {
    case library
    case general
    case shortcuts
    case mcp
    case cli
    case about

    var title: String {
        NSLocalizedString(titleKey, comment: "")
    }

    private var titleKey: String {
        switch self {
        case .library: return "console.sidebar.library"
        case .general: return "console.sidebar.general"
        case .shortcuts: return "console.sidebar.shortcuts"
        case .mcp: return "console.mcp.navTitle"
        case .cli: return "console.cli.navTitle"
        case .about: return "console.about.title"
        }
    }

    var symbol: String {
        switch self {
        case .library: return "square.grid.2x2"
        case .general: return "gearshape"
        case .shortcuts: return "keyboard"
        case .mcp: return "terminal"
        case .cli: return "terminal"
        case .about: return "info.circle"
        }
    }

    /// 侧栏图标资源名（bundle 内 template PNG）；有值时优先于 SF Symbol。
    /// MCP 使用官方标志，CLI 沿用原来的终端符号。
    var iconAsset: String? {
        switch self {
        case .mcp: return "MCPIcon"
        default: return nil
        }
    }
}

/// 服务页面统一的显示刷新入口；无状态页面使用默认空实现。
@MainActor
protocol ConsoleServicePage: NSView {
    func activate()
}

extension ConsoleServicePage {
    func activate() {}
}
