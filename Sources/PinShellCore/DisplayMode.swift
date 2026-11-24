import Foundation

/// 模板的展示方式（全局设置，持久化在 UserDefaults）。
/// rawValue 是持久化契约，已有取值不可修改。
public enum DisplayMode: String, CaseIterable, Sendable {
    /// 始终置顶的桌面悬浮层（原有行为）。
    case desktop
    /// 点击菜单栏图标后，面板锚定在图标下方弹出。
    case menuBar
}
