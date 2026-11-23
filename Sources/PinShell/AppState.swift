import AppKit

/// UserDefaults 持久化（spec 2.5）：窗口 frame / 上次 HTML 路径 / 穿透开关 / 更新检查
enum AppState {
    private static let kFrame = "windowFrame"
    private static let kHTMLPath = "lastHTMLPath"
    private static let kPassthrough = "passthroughEnabled"
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
