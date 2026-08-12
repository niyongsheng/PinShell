import AppKit

/// UserDefaults 持久化（spec 2.5）：窗口 frame / 上次 HTML 路径 / 穿透开关 / 更新检查
enum AppState {
    private static let kFrame = "windowFrame"
    private static let kHTMLPath = "lastHTMLPath"
    private static let kPassthrough = "passthroughEnabled"
    private static let kPassthroughOpacity = "passthroughOpacity"
    private static let kLastUpdateCheck = "lastUpdateCheckDate"
    private static let kSkippedVersion = "skippedUpdateVersion"

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

    /// 穿透模式透明度（CSS 变量 --ps-passthrough-opacity，0.3~1.0）。
    /// 默认值经 register(defaults:) 注册，getter 无需哨兵判断（见 registerDefaults）
    static var passthroughOpacity: Double {
        get { UserDefaults.standard.double(forKey: kPassthroughOpacity) }
        set { UserDefaults.standard.set(newValue, forKey: kPassthroughOpacity) }
    }

    /// 一次性注册默认值（首次访问 AppState 时执行）。0.65 与 design-tokens.css
    /// 的 --ps-passthrough-opacity 保持一致（模板侧兜底），改动需两处同步
    static let registerDefaults: Void = {
        UserDefaults.standard.register(defaults: [kPassthroughOpacity: 0.65])
    }()

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
}
