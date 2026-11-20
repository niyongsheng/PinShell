import Foundation

/// 窗口尺寸（点）。HTML meta / CLI 的统一解析结果。
public struct WindowSize: Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public static let minimum = WindowSize(width: 80, height: 40)
    public static let fallback = WindowSize(width: 240, height: 80)

    /// 支持 "280x64" / "280*64" / "280,64"，单位 pt。
    public static func parse(_ raw: String) -> WindowSize? {
        let separators = CharacterSet(charactersIn: "x×,*")
        let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard parts.count == 2,
              let width = Double(parts[0]),
              let height = Double(parts[1]),
              width.isFinite, height.isFinite,
              width > 0, height > 0 else { return nil }
        return WindowSize(width: width, height: height)
    }
}

/// 九宫格锚点（macOS 坐标：原点左下、y 向上）。
public enum WindowAnchor: String, CaseIterable, Sendable {
    case topLeft = "top-left"
    case top = "top"
    case topRight = "top-right"
    case left = "left"
    case center = "center"
    case right = "right"
    case bottomLeft = "bottom-left"
    case bottom = "bottom"
    case bottomRight = "bottom-right"

    public init?(normalized raw: String) {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        self.init(rawValue: key)
    }

    public var isLeft: Bool { self == .topLeft || self == .left || self == .bottomLeft }
    public var isRight: Bool { self == .topRight || self == .right || self == .bottomRight }
    public var isTop: Bool { self == .topLeft || self == .top || self == .topRight }
    public var isBottom: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }
}

/// 位置：绝对坐标（全局屏幕坐标）或九宫格锚点。
public enum WindowPosition: Equatable, Sendable {
    case absolute(x: Double, y: Double)
    case anchor(WindowAnchor)

    /// 支持 "bottom-right" / "top_left" / "120,240" / "120 240"。
    public static func parse(_ raw: String) -> WindowPosition? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let anchor = WindowAnchor(normalized: trimmed) {
            return .anchor(anchor)
        }
        let parts = trimmed
            .components(separatedBy: CharacterSet(charactersIn: ", "))
            .filter { !$0.isEmpty }
        guard parts.count == 2,
              let x = Double(parts[0]),
              let y = Double(parts[1]),
              x.isFinite, y.isFinite else { return nil }
        return .absolute(x: x, y: y)
    }
}

/// 与 AppKit 解耦的 CGRect 等价物，便于核心层单测。
public struct WindowFrame: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var size: WindowSize { WindowSize(width: width, height: height) }
}

/// 声明式窗口属性（HTML meta / CLI 参数）。
public struct WindowSpec: Equatable, Sendable {
    public var size: WindowSize?
    public var position: WindowPosition?
    public var passthrough: Bool?
    public var opacity: Double?
    public var radius: Double?

    public init(size: WindowSize? = nil,
                position: WindowPosition? = nil,
                passthrough: Bool? = nil,
                opacity: Double? = nil,
                radius: Double? = nil) {
        self.size = size
        self.position = position
        self.passthrough = passthrough
        self.opacity = opacity
        self.radius = radius
    }

    public static let empty = WindowSpec()

    public var isEmpty: Bool {
        size == nil && position == nil && passthrough == nil && opacity == nil && radius == nil
    }

    /// 逐字段合并：overrides 优先，nil 表示沿用 base。
    public func merging(overrides: WindowSpec?) -> WindowSpec {
        guard let overrides else { return self }
        return WindowSpec(
            size: overrides.size ?? size,
            position: overrides.position ?? position,
            passthrough: overrides.passthrough ?? passthrough,
            opacity: overrides.opacity ?? opacity,
            radius: overrides.radius ?? radius
        )
    }
}

public enum WindowGeometry {
    public static let defaultInset: Double = 24

    /// 解析最终 frame：
    /// - size 单独声明 → 保留当前原点；position 单独声明 → 保留当前尺寸；
    /// - 锚点相对传入 screen 计算；绝对坐标直接使用；
    /// - 结果完整 clamp 到 screen，并保证不小于最小尺寸。
    public static func resolve(size: WindowSize?,
                               position: WindowPosition?,
                               current: WindowFrame,
                               screen: WindowFrame,
                               inset: Double = defaultInset) -> WindowFrame {
        let maxWidth = max(screen.width, WindowSize.minimum.width)
        let maxHeight = max(screen.height, WindowSize.minimum.height)

        var width = size?.width ?? current.width
        var height = size?.height ?? current.height
        width = min(max(width, WindowSize.minimum.width), maxWidth)
        height = min(max(height, WindowSize.minimum.height), maxHeight)

        var x = current.x
        var y = current.y

        switch position {
        case .absolute(let px, let py):
            x = px
            y = py
        case .anchor(let anchor):
            if anchor.isLeft {
                x = screen.minX + inset
            } else if anchor.isRight {
                x = screen.maxX - width - inset
            } else {
                x = screen.minX + (screen.width - width) / 2
            }
            if anchor.isBottom {
                y = screen.minY + inset
            } else if anchor.isTop {
                y = screen.maxY - height - inset
            } else {
                y = screen.minY + (screen.height - height) / 2
            }
        case nil:
            break
        }

        // 程序化 frame 完整落在目标屏幕内；手动拖动不经过这里，保留原有自由行为
        x = min(max(x, screen.minX), max(screen.minX, screen.maxX - width))
        y = min(max(y, screen.minY), max(screen.minY, screen.maxY - height))

        return WindowFrame(x: x, y: y, width: width, height: height)
    }
}
