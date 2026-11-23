import AppKit

/// 控制台视觉 token：颜色、圆角、间距、字体。
///
/// 设计基调是原生 macOS 精致风：页面内用「珍珠白卡片 + 发丝线」分层，
/// 窗口保留系统 vibrancy；玻璃材质只留给 sheet / 浮层（GlassCard）。
/// 交互强调色跟随系统 `controlAccentColor`，状态用系统语义色。
enum ConsoleTheme {

    // MARK: - 颜色

    enum Color {
        /// 页面内卡片底色：浅色近白，深色用一层低透明度白叠在 vibrancy 上。
        static let cardFill = dynamic(
            light: NSColor.white.withAlphaComponent(0.82),
            dark: NSColor.white.withAlphaComponent(0.055)
        )

        /// 浮起表面（进度条、浮层卡片）。
        static let cardFillElevated = dynamic(
            light: NSColor.white.withAlphaComponent(0.94),
            dark: NSColor(calibratedWhite: 0.16, alpha: 0.94)
        )

        /// 卡片 / 输入框描边。
        static let cardStroke = dynamic(
            light: NSColor.black.withAlphaComponent(0.10),
            dark: NSColor.white.withAlphaComponent(0.12)
        )

        /// 代码块、路径块的内嵌表面。
        static let insetFill = dynamic(
            light: NSColor(calibratedWhite: 0.0, alpha: 0.04),
            dark: NSColor.white.withAlphaComponent(0.06)
        )

        static let iconTileFill = dynamic(
            light: NSColor(calibratedWhite: 0.0, alpha: 0.045),
            dark: NSColor.white.withAlphaComponent(0.07)
        )

        /// 预览舞台渐变（浅色像摄影棚背景，深色收进石墨色）。
        static let stageTop = dynamic(
            light: NSColor(srgbRed: 0.969, green: 0.973, blue: 0.980, alpha: 1),
            dark: NSColor(srgbRed: 0.149, green: 0.149, blue: 0.165, alpha: 1)
        )
        static let stageBottom = dynamic(
            light: NSColor(srgbRed: 0.875, green: 0.894, blue: 0.925, alpha: 1),
            dark: NSColor(srgbRed: 0.106, green: 0.106, blue: 0.118, alpha: 1)
        )

        static let accent = NSColor.controlAccentColor
        static let positive = NSColor.systemGreen
        static let warning = NSColor.systemOrange
        static let destructive = NSColor.systemRed
        static let info = NSColor.systemBlue

        /// 品牌红只用于 Logo / 爱心图标等点缀，不用于交互强调。
        static let brandRed = NSColor(srgbRed: 0.992, green: 0.208, blue: 0.196, alpha: 1)

        /// 发丝线（1px 分隔）。
        static let hairline = dynamic(
            light: NSColor.black.withAlphaComponent(0.08),
            dark: NSColor.white.withAlphaComponent(0.10)
        )

        /// 彩色按钮上的文字颜色：按底色亮度选黑/白，避免黄色强调色下白字看不清。
        static func contrastingLabel(on background: NSColor) -> NSColor {
            guard let rgb = background.usingColorSpace(.sRGB) else { return .white }
            let luminance = 0.2126 * rgb.redComponent
                + 0.7152 * rgb.greenComponent
                + 0.0722 * rgb.blueComponent
            return luminance > 0.6 ? .black : .white
        }

        /// 根据外观生成动态颜色。
        static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
            NSColor(name: nil) { appearance in
                let match = appearance.bestMatch(from: [.darkAqua, .aqua])
                return match == .darkAqua ? dark : light
            }
        }
    }

    // MARK: - 圆角

    enum Radius {
        static let card: CGFloat = 16
        static let stage: CGFloat = 12
        static let control: CGFloat = 10
        static let iconTile: CGFloat = 10
        static let pill: CGFloat = 999
    }

    // MARK: - 间距

    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32

        static let pageInset: CGFloat = 24
        static let cardInset: CGFloat = 18
        static let stageInset: CGFloat = 12
        static let previewCardInset: CGFloat = 10
    }

    // MARK: - 字体

    enum Font {
        static let pageTitle = NSFont.systemFont(ofSize: 26, weight: .semibold)
        static let pageSubtitle = NSFont.systemFont(ofSize: 12.5, weight: .regular)
        static let sectionTitle = NSFont.systemFont(ofSize: 13, weight: .semibold)
        static let rowTitle = NSFont.systemFont(ofSize: 13, weight: .semibold)
        static let body = NSFont.systemFont(ofSize: 12.5, weight: .regular)
        static let caption = NSFont.systemFont(ofSize: 11, weight: .regular)
        static let micro = NSFont.systemFont(ofSize: 10.5, weight: .regular)
        static let chip = NSFont.systemFont(ofSize: 11, weight: .medium)
        static let button = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        static let monoCode = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
        static let monoMeta = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)

        /// 大标题用的轻微负字距（中文同样适用，视觉更紧凑）。
        static func tracked(_ text: String,
                            font: NSFont,
                            color: NSColor = .labelColor,
                            tracking: CGFloat = -0.3) -> NSAttributedString {
            NSAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: color,
                .kern: tracking,
            ])
        }
    }

    // MARK: - 分类符号

    /// 在线模板库分类 → SF Symbol（全部为 macOS 13 可用的稳定符号）。
    static func categorySymbol(for id: String?) -> String {
        switch id {
        case "productivity": return "checklist"
        case "focus": return "timer"
        case "monitoring": return "gauge"
        case "companion": return "person.2"
        case "media": return "play.rectangle"
        case "play": return "gamecontroller"
        case "social": return "bubble.left.and.bubble.right"
        default: return "square.grid.2x2"
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
