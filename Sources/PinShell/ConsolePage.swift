import AppKit

/// 控制台服务页面：侧边栏、详情页与快捷键共用同一套目的地。
enum ConsolePage {
    case library
    case general
    case shortcuts
    case mcp
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
        case .about: return "console.about.title"
        }
    }

    var symbol: String {
        switch self {
        case .library: return "square.grid.2x2"
        case .general: return "gearshape"
        case .shortcuts: return "keyboard"
        case .mcp: return "terminal"
        case .about: return "info.circle"
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
