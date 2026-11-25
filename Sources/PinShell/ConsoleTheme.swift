import AppKit

/// 控制台视觉 token：颜色、圆角、间距、字体。
///
/// 设计基调对齐 macOS 系统设置：侧边栏保留系统 source list 与 vibrancy，
/// 详情页用不透明页面底色 + 分组卡片 + 发丝分隔线；交互强调色跟随系统
/// `controlAccentColor`，状态用系统语义色。
enum ConsoleTheme {

    // MARK: - 颜色

    enum Color {
        /// 详情页 / 编辑器的不透明页面底色（浅灰 / 石墨）。
        /// 不用 `underPageBackgroundColor`：在 vibrancy 窗口里它会解析成半透明灰。
        static let pageBackground = dynamic(
            light: NSColor(srgbRed: 0.965, green: 0.965, blue: 0.965, alpha: 1),
            dark: NSColor(srgbRed: 0.157, green: 0.157, blue: 0.157, alpha: 1)
        )

        /// 分组卡片底色：浅色纯白，深色比页面底色深一层。
        static let cardFill = dynamic(
            light: .white,
            dark: NSColor(srgbRed: 0.118, green: 0.118, blue: 0.118, alpha: 1)
        )

        /// 卡片描边与分隔线。
        static let cardStroke = dynamic(
            light: NSColor.black.withAlphaComponent(0.10),
            dark: NSColor.white.withAlphaComponent(0.12)
        )

        /// 代码块、路径块、可点击行 hover 的内嵌表面。
        static let insetFill = dynamic(
            light: NSColor(calibratedWhite: 0.0, alpha: 0.04),
            dark: NSColor.white.withAlphaComponent(0.06)
        )

        /// 预览舞台渐变：页面底色 → 卡片底色，保持低对比的原生观感。
        static let stageTop = pageBackground
        static let stageBottom = cardFill

        static let accent = NSColor.controlAccentColor
        static let positive = NSColor.systemGreen
        static let warning = NSColor.systemOrange
        static let destructive = NSColor.systemRed
        static let info = NSColor.systemBlue

        /// macOS 窗口交通灯圆点色：关闭红 / 最小化黄 / 缩放绿。
        /// 关于页「赞助 / 收藏 / 分享」沿用这套色值，按红黄绿从左到右排列。
        static let trafficRed = NSColor(srgbRed: 1, green: 0.373, blue: 0.341, alpha: 1)
        static let trafficYellow = NSColor(srgbRed: 0.996, green: 0.737, blue: 0.180, alpha: 1)
        static let trafficGreen = NSColor(srgbRed: 0.157, green: 0.784, blue: 0.251, alpha: 1)

        /// 彩色按钮上的文字颜色：按底色亮度选黑/白，避免黄色强调色下白字看不清。
        static func contrastingLabel(on background: NSColor) -> NSColor {
            guard let rgb = background.usingColorSpace(.sRGB) else { return .white }
            let luminance = 0.2126 * rgb.redComponent
                + 0.7152 * rgb.greenComponent
                + 0.0722 * rgb.blueComponent
            return luminance > 0.6 ? .black : .white
        }

        static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
            NSColor(name: nil) { appearance in
                let match = appearance.bestMatch(from: [.darkAqua, .aqua])
                return match == .darkAqua ? dark : light
            }
        }
    }

    // MARK: - 圆角

    enum Radius {
        static let card: CGFloat = 10
        static let stage: CGFloat = 8
        static let control: CGFloat = 6
    }

    // MARK: - 间距

    enum Space {
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32

        static let pageInset: CGFloat = 20
        static let cardInset: CGFloat = 16
        static let stageInset: CGFloat = 8

        /// 系统设置式分组行节奏。
        static let rowHeight: CGFloat = 44
        static let rowInset: CGFloat = 16
        static let groupSpacing: CGFloat = 24
        static let groupHeaderGap: CGFloat = 8
        static let sidebarRowHeight: CGFloat = 28
        static let sidebarSectionHeight: CGFloat = 26
        static let formRowHeight: CGFloat = 36
    }

    // MARK: - 字体

    enum Font {
        static let pageTitle = NSFont.systemFont(ofSize: 22, weight: .semibold)
        static let pageSubtitle = NSFont.systemFont(ofSize: 13, weight: .regular)
        static let sectionTitle = NSFont.systemFont(ofSize: 13, weight: .semibold)
        static let rowTitle = NSFont.systemFont(ofSize: 13, weight: .regular)
        static let body = NSFont.systemFont(ofSize: 13, weight: .regular)
        static let caption = NSFont.systemFont(ofSize: 11, weight: .regular)
        static let chip = NSFont.systemFont(ofSize: 11, weight: .medium)
        static let monoCode = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        static let monoMeta = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        static let sidebarItem = NSFont.systemFont(ofSize: 13, weight: .regular)
        static let sidebarSection = NSFont.systemFont(ofSize: 11, weight: .semibold)
        static let sidebarBadge = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        static let editorTitle = NSFont.systemFont(ofSize: 17, weight: .semibold)
        static let emptyTitle = NSFont.systemFont(ofSize: 15, weight: .semibold)

        /// 大标题用的轻微负字距（中文同样适用，视觉更紧凑）。
        static func tracked(_ text: String,
                            font: NSFont,
                            color: NSColor = .labelColor,
                            tracking: CGFloat = -0.2) -> NSAttributedString {
            NSAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: color,
                .kern: tracking,
            ])
        }
    }

    // MARK: - 分类样式

    /// 分类图标块：SF Symbol + 系统色，同一张表避免符号与颜色各自漂移。
    struct CategoryStyle {
        let symbol: String
        let tint: NSColor
    }

    /// 在线模板库分类 → 图标样式（全部为 macOS 13 可用的稳定符号）。
    static func categoryStyle(for id: String?) -> CategoryStyle {
        switch id {
        case "productivity":
            return CategoryStyle(symbol: "checklist", tint: .systemBlue)
        case "focus":
            return CategoryStyle(symbol: "timer", tint: .systemOrange)
        case "monitoring":
            return CategoryStyle(symbol: "gauge", tint: .systemGreen)
        case "companion":
            return CategoryStyle(symbol: "person.2", tint: .systemPink)
        case "media":
            return CategoryStyle(symbol: "play.rectangle", tint: .systemPurple)
        case "play":
            return CategoryStyle(symbol: "gamecontroller", tint: .systemRed)
        case "social":
            return CategoryStyle(symbol: "bubble.left.and.bubble.right", tint: .systemTeal)
        case "other":
            return CategoryStyle(symbol: "ellipsis.circle", tint: .systemGray)
        default:
            return CategoryStyle(symbol: "square.grid.2x2", tint: .systemGray)
        }
    }
}

// MARK: - 外观切换辅助

extension NSView {
    /// 把动态颜色写进 CGColor 后，切换深浅色时需要重新解析。
    func performWithEffectiveAppearance(_ body: () -> Void) {
        effectiveAppearance.performAsCurrentDrawingAppearance(body)
    }
}
