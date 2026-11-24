import Foundation

/// 菜单栏弹出面板的纯几何计算：顶部居中锚定在状态栏图标下方，
/// 并把 frame clamp 到目标屏幕的可见区域内。
///
/// 不依赖 AppKit，便于在 PinShellCore 单测里覆盖多屏 / 负坐标 / 极端尺寸。
public enum MenuBarPopoverGeometry {
    /// 面板顶部与菜单栏之间的间距（pt）。
    public static let defaultGap: Double = 6
    /// 面板与屏幕左右/底部之间的最小间距（pt）。
    public static let defaultInset: Double = 8

    /// - Parameters:
    ///   - size: 模板声明的面板尺寸（会被 clamp 到最小尺寸与屏幕可用区域）。
    ///   - iconFrame: 状态栏按钮在屏幕坐标中的 frame；nil 时回落到屏幕顶部中央。
    ///   - visibleFrame: 图标所在屏幕的 visibleFrame（已排除菜单栏/Dock）。
    ///   - gap: 面板顶部与图标底边之间的间距。
    ///   - inset: 面板与屏幕左右/底部边缘的最小间距。
    /// - Returns: 面板最终的屏幕坐标 frame（原点左下，与 AppKit 一致）。
    public static func resolve(size: WindowSize,
                               iconFrame: WindowFrame?,
                               visibleFrame: WindowFrame,
                               gap: Double = defaultGap,
                               inset: Double = defaultInset) -> WindowFrame {
        let gap = max(gap.isFinite ? gap : 0, 0)
        let inset = max(inset.isFinite ? inset : 0, 0)

        let rawWidth = size.width.isFinite ? size.width : WindowSize.minimum.width
        let rawHeight = size.height.isFinite ? size.height : WindowSize.minimum.height

        let minX = visibleFrame.minX + inset
        let maxWidth = max(visibleFrame.width - 2 * inset, WindowSize.minimum.width)
        let width = min(max(rawWidth, WindowSize.minimum.width), maxWidth)

        // 图标在菜单栏里，visibleFrame.maxY 是菜单栏底边；两者取小，
        // 兼容连接外接屏后状态栏窗口短暂返回旧 Y 值的情况。
        let anchorBottom = min(iconFrame?.minY ?? visibleFrame.maxY, visibleFrame.maxY)
        let minY = visibleFrame.minY + inset
        let maxHeight = max(anchorBottom - gap - minY, WindowSize.minimum.height)
        let height = min(max(rawHeight, WindowSize.minimum.height), maxHeight)

        let anchorX = iconFrame.map { $0.x + $0.width / 2 }
            ?? (visibleFrame.x + visibleFrame.width / 2)
        let maxX = max(minX, visibleFrame.maxX - inset - width)
        let x = min(max(anchorX - width / 2, minX), maxX)

        // 顶部由 gap 锚定，不再套用 inset；这里只兜底保证不越出屏幕。
        let maxY = max(minY, visibleFrame.maxY - height)
        let y = min(max(anchorBottom - gap - height, minY), maxY)

        return WindowFrame(x: x, y: y, width: width, height: height)
    }
}
