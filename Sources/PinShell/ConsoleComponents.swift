import AppKit
import PinShellCore

extension WindowAnchor {
    /// 控制台与编辑器共用的本地化名称。
    var displayName: String {
        let key: String
        switch self {
        case .topLeft: key = "console.anchor.topLeft"
        case .top: key = "console.anchor.top"
        case .topRight: key = "console.anchor.topRight"
        case .left: key = "console.anchor.left"
        case .center: key = "console.anchor.center"
        case .right: key = "console.anchor.right"
        case .bottomLeft: key = "console.anchor.bottomLeft"
        case .bottom: key = "console.anchor.bottom"
        case .bottomRight: key = "console.anchor.bottomRight"
        }
        return NSLocalizedString(key, comment: "")
    }
}

extension WindowPosition {
    /// 锚点名，或 "x,y" 形式的绝对坐标。
    var displayName: String {
        switch self {
        case .anchor(let anchor): return anchor.displayName
        case .absolute(let x, let y):
            return "\(NumberFormat.text(x)),\(NumberFormat.text(y))"
        }
    }
}

/// 液态玻璃卡片：macOS 26+ 用 NSGlassEffectView，旧系统回退到 NSVisualEffectView。
/// 内容统一内缩 16pt；调用方把自己的 stack 加进 `contentView` 并铺满即可。
final class GlassCard: NSView {
    let contentView = NSView()

    init(cornerRadius: CGFloat = 18) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor

        let backing: NSView
        let glassOwnsContent: Bool
        // NSGlassEffectView 来自 macOS 26 SDK（Swift 6.2）；旧 Xcode/CI runner 走视觉特效回退
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = cornerRadius
            glass.tintColor = NSColor.white.withAlphaComponent(0.04)
            backing = glass
            glassOwnsContent = true
            glass.contentView = contentView
        } else {
            backing = Self.makeVisualEffect(cornerRadius: cornerRadius)
            glassOwnsContent = false
        }
        #else
        backing = Self.makeVisualEffect(cornerRadius: cornerRadius)
        glassOwnsContent = false
        #endif

        addSubview(backing)
        backing.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            backing.leadingAnchor.constraint(equalTo: leadingAnchor),
            backing.trailingAnchor.constraint(equalTo: trailingAnchor),
            backing.topAnchor.constraint(equalTo: topAnchor),
            backing.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        contentView.translatesAutoresizingMaskIntoConstraints = false
        if !glassOwnsContent {
            backing.addSubview(contentView)
        }
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: backing.leadingAnchor, constant: 16),
            contentView.trailingAnchor.constraint(equalTo: backing.trailingAnchor, constant: -16),
            contentView.topAnchor.constraint(equalTo: backing.topAnchor, constant: 16),
            contentView.bottomAnchor.constraint(equalTo: backing.bottomAnchor, constant: -16),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private static func makeVisualEffect(cornerRadius: CGFloat) -> NSVisualEffectView {
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .withinWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = cornerRadius
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        return effect
    }
}

/// 状态胶囊：SF Symbol 图标 + 文案，用颜色表达开/关。
final class StatusChip: NSView {
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.08).cgColor

        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 10),
            iconView.heightAnchor.constraint(equalToConstant: 10),
        ])

        label.font = .systemFont(ofSize: 10.5, weight: .medium)
        label.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [iconView, label])
        stack.orientation = .horizontal
        stack.spacing = 5
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 3, left: 8, bottom: 3, right: 9)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(text: String, active: Bool, activeColor: NSColor = .systemGreen,
                symbol: String? = nil) {
        label.stringValue = text
        label.textColor = active ? .labelColor : .secondaryLabelColor

        let name = symbol ?? (active ? "circle.fill" : "circle")
        let configuration = NSImage.SymbolConfiguration(pointSize: 7, weight: .semibold)
        iconView.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        iconView.contentTintColor = active ? activeColor : .tertiaryLabelColor
        layer?.backgroundColor = (active
            ? activeColor.withAlphaComponent(0.10)
            : NSColor.quaternaryLabelColor.withAlphaComponent(0.08)).cgColor
    }
}

/// 统一的小号图标按钮（SF Symbols）。
func makeSymbolButton(symbol: String,
                      title: String? = nil,
                      target: AnyObject?,
                      action: Selector) -> NSButton {
    let button = NSButton(title: title ?? "", target: target, action: action)
    button.bezelStyle = .rounded
    button.controlSize = .regular
    button.font = .systemFont(ofSize: 12, weight: .medium)
    button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
    button.imagePosition = title == nil ? .imageOnly : .imageLeading
    return button
}

/// 翻转坐标的 stack：作为滚动视图的文档视图，内容从顶部向下排列。
final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

/// 翻转坐标的普通视图：作滚动文档容器，让内容从顶部开始排。
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// 控制台详情页的滚动容器：内容自上而下排列，左右留白 22pt、顶部 4pt。
/// 文档视图必须与 clip view 同宽且原点为 0，留白由内层 stack 承担，
/// 否则 NSClipView 会把带偏移的文档视图滚到左边缘，左边距变 0。
final class ConsoleScrollPage: NSView {
    let stack = FlippedStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func build() {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14

        let document = FlippedView()
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.documentView = document
        document.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        addSubview(scroll)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),

            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),

            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -22),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
        ])
    }
}

/// 小标题：SF Symbol + 文案，用于卡片内分区。
func makeSectionLabel(_ text: String, symbol: String? = nil) -> NSView {
    let label = NSTextField(labelWithString: text)
    label.font = .systemFont(ofSize: 11, weight: .semibold)
    label.textColor = .secondaryLabelColor

    guard let symbol,
          let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)) else {
        return label
    }
    let icon = NSImageView(image: image)
    icon.contentTintColor = .secondaryLabelColor
    icon.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        icon.widthAnchor.constraint(equalToConstant: 12),
        icon.heightAnchor.constraint(equalToConstant: 12),
    ])
    let stack = NSStackView(views: [icon, label])
    stack.orientation = .horizontal
    stack.spacing = 5
    stack.alignment = .centerY
    return stack
}
