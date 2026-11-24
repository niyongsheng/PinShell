import AppKit
import PinShellCore

/// UserDefaults 持久化（spec 2.5）：窗口 frame / 上次 HTML 路径 / 穿透开关 / 显示方式 / 更新检查
enum AppState {
    private static let kFrame = "windowFrame"
    private static let kHTMLPath = "lastHTMLPath"
    private static let kPassthrough = "passthroughEnabled"
    private static let kDisplayMode = "displayMode"
    private static let kLastUpdateCheck = "lastUpdateCheckDate"
    private static let kSkippedVersion = "skippedUpdateVersion"
    private static let kAnalyticsEnabled = "analyticsEnabled"
    private static let kAppearance = "appAppearance"
    private static let kBundledSeedVersion = "bundledSeedVersion"

    static var windowFrame: NSRect? {
        get {
            guard let s = UserDefaults.standard.string(forKey: kFrame) else { return nil }
            return NSRectFromString(s)
        }
        set { UserDefaults.standard.set(newValue.map(NSStringFromRect), forKey: kFrame) }
    }

    static var lastHTMLURL: URL? {
        get {
            guard let p = UserDefaults.standard.string(forKey: kHTMLPath) else { return nil }
            return URL(fileURLWithPath: p)
        }
        set { UserDefaults.standard.set(newValue?.path, forKey: kHTMLPath) }
    }

    /// 默认关闭（spec 2.6：首次启动即可编辑拖动窗口）
    static var passthroughEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: kPassthrough) }
        set { UserDefaults.standard.set(newValue, forKey: kPassthrough) }
    }

    /// 模板展示方式：桌面悬浮 / 菜单栏弹出。老用户无此 key，默认保持原有行为。
    static var displayMode: DisplayMode {
        get {
            DisplayMode(rawValue: UserDefaults.standard.string(forKey: kDisplayMode) ?? "")
                ?? .desktop
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: kDisplayMode) }
    }

    /// 用户是否显式选择过展示方式；首装内置模板需要区分“未设置”和“已选择桌面悬浮”。
    static var hasDisplayModePreference: Bool {
        UserDefaults.standard.object(forKey: kDisplayMode) != nil
    }

    /// 上次自动检查更新的时间（距今 ≤24h 不再重复检查）
    static var lastUpdateCheckDate: Date? {
        get { UserDefaults.standard.object(forKey: kLastUpdateCheck) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: kLastUpdateCheck) }
    }

    /// 用户选择"跳过此版本"的版本号（该版本不再提醒）
    static var skippedVersion: String? {
        get { UserDefaults.standard.string(forKey: kSkippedVersion) }
        set { UserDefaults.standard.set(newValue, forKey: kSkippedVersion) }
    }

    /// 匿名使用统计开关：默认开启，老用户没有该 key 时同样视为开启。
    static var analyticsEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: kAnalyticsEnabled) as? Bool ?? true
        }
        set { UserDefaults.standard.set(newValue, forKey: kAnalyticsEnabled) }
    }

    /// 应用外观：自动跟随系统 / 浅色 / 深色。默认跟随系统。
    static var appearance: AppAppearance {
        get {
            AppAppearance(rawValue: UserDefaults.standard.string(forKey: kAppearance) ?? "")
                ?? .system
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: kAppearance) }
    }

    static var bundledSeedVersion: Int {
        get { UserDefaults.standard.integer(forKey: kBundledSeedVersion) }
        set { UserDefaults.standard.set(newValue, forKey: kBundledSeedVersion) }
    }
}

/// 应用外观偏好；`system` 跟随系统，其余强制指定。
enum AppAppearance: String, CaseIterable {
    case system
    case light
    case dark

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil                // nil = 跟随系统
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    /// 立即应用到整个应用：控制台、悬浮窗以及网页的 prefers-color-scheme 同步切换。
    func apply() {
        NSApp.appearance = nsAppearance
    }
}
