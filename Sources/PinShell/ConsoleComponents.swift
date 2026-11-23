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

// MARK: - 卡片与容器

/// 液态玻璃卡片：macOS 26+ 用 NSGlassEffectView，旧系统回退到 NSVisualEffectView。
/// 只用于 sheet / 浮层；页面内请用 ConsoleCard。
final class GlassCard: NSView {
    let contentView = NSView()

    init(cornerRadius: CGFloat = 18, inset: CGFloat = 16) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        layer?.borderColor = ConsoleTheme.Color.cardStroke.cgColor

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
            contentView.leadingAnchor.constraint(equalTo: backing.leadingAnchor, constant: inset),
            contentView.trailingAnchor.constraint(equalTo: backing.trailingAnchor, constant: -inset),
            contentView.topAnchor.constraint(equalTo: backing.topAnchor, constant: inset),
            contentView.bottomAnchor.constraint(equalTo: backing.bottomAnchor, constant: -inset),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        performWithEffectiveAppearance { [weak self] in
            self?.layer?.borderColor = ConsoleTheme.Color.cardStroke.cgColor
        }
    }

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

/// 页面内标准卡片：珍珠白表面 + 发丝线，不投影。内容内缩由 `inset` 控制。
final class ConsoleCard: NSView {
    let contentView = NSView()
    private let fill: NSColor
    private let stroke: NSColor

    init(cornerRadius: CGFloat = ConsoleTheme.Radius.card,
         inset: NSEdgeInsets = NSEdgeInsets(top: ConsoleTheme.Space.cardInset,
                                           left: ConsoleTheme.Space.cardInset,
                                           bottom: ConsoleTheme.Space.cardInset,
                                           right: ConsoleTheme.Space.cardInset),
         fill: NSColor = ConsoleTheme.Color.cardFill,
         stroke: NSColor = ConsoleTheme.Color.cardStroke) {
        self.fill = fill
        self.stroke = stroke
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset.left),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset.right),
            contentView.topAnchor.constraint(equalTo: topAnchor, constant: inset.top),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset.bottom),
        ])
        applySurface()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        performWithEffectiveAppearance { [weak self] in
            self?.applySurface()
        }
    }

    private func applySurface() {
        layer?.backgroundColor = fill.cgColor
        layer?.borderColor = stroke.cgColor
    }
}

/// 内嵌表面（代码块、路径块）：比卡片更深一层，无描边。
final class ConsoleInsetView: NSView {
    let contentView = NSView()

    init(inset: NSEdgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12),
         cornerRadius: CGFloat = ConsoleTheme.Radius.control) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset.left),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset.right),
            contentView.topAnchor.constraint(equalTo: topAnchor, constant: inset.top),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset.bottom),
        ])
        applySurface()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        performWithEffectiveAppearance { [weak self] in
            self?.applySurface()
        }
    }

    private func applySurface() {
        layer?.backgroundColor = ConsoleTheme.Color.insetFill.cgColor
    }
}

/// 预览舞台：柔和渐变底 + 发丝线，让模板像放在摄影棚里。
final class ConsoleStageView: NSView {
    let contentView = NSView()

    init(cornerRadius: CGFloat = ConsoleTheme.Radius.stage,
         inset: CGFloat = ConsoleTheme.Space.stageInset) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        layer?.masksToBounds = true

        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            contentView.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
        ])
        applyBorder()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let gradient = NSGradient(starting: ConsoleTheme.Color.stageTop,
                                  ending: ConsoleTheme.Color.stageBottom)
        gradient?.draw(in: bounds, angle: -90)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        performWithEffectiveAppearance { [weak self] in
            self?.applyBorder()
        }
        needsDisplay = true
    }

    private func applyBorder() {
        layer?.borderColor = ConsoleTheme.Color.cardStroke.cgColor
    }
}

/// 1px 发丝线。
final class HairlineView: NSView {
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 1).isActive = true
        applyColor()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        performWithEffectiveAppearance { [weak self] in
            self?.applyColor()
        }
    }

    private func applyColor() {
        layer?.backgroundColor = ConsoleTheme.Color.hairline.cgColor
    }
}

// MARK: - 图标块 / 页头 / 空态

/// 圆角图标底块。
final class ConsoleIconTile: NSView {
    enum Style { case neutral, accent }

    private let imageView = NSImageView()
    private let style: Style

    init(symbol: String,
         size: CGFloat = 36,
         symbolPointSize: CGFloat = 16,
         style: Style = .neutral) {
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = ConsoleTheme.Radius.iconTile
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: size).isActive = true
        heightAnchor.constraint(equalToConstant: size).isActive = true

        imageView.imageScaling = .scaleProportionallyDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: symbolPointSize),
            imageView.heightAnchor.constraint(equalToConstant: symbolPointSize),
        ])
        setSymbol(symbol, pointSize: symbolPointSize)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setSymbol(_ name: String, pointSize: CGFloat = 16) {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        imageView.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        applyColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        performWithEffectiveAppearance { [weak self] in
            self?.applyColors()
        }
    }

    private func applyColors() {
        switch style {
        case .neutral:
            layer?.backgroundColor = ConsoleTheme.Color.iconTileFill.cgColor
            imageView.contentTintColor = .secondaryLabelColor
        case .accent:
            layer?.backgroundColor = ConsoleTheme.Color.accent.withAlphaComponent(0.12).cgColor
            imageView.contentTintColor = ConsoleTheme.Color.accent
        }
    }
}

/// 页面头：图标块 + 标题 + 副标题 + 右侧 accessory。MCP / 模板库共用。
final class PageHeader: NSView {
    private let titleLabel: NSTextField
    private let subtitleLabel = NSTextField(wrappingLabelWithString: "")

    init(symbol: String,
         title: String,
         subtitle: String? = nil,
         accessory: NSView? = nil,
         iconSize: CGFloat = 40) {
        titleLabel = NSTextField(labelWithAttributedString:
            ConsoleTheme.Font.tracked(title, font: ConsoleTheme.Font.pageTitle))
        super.init(frame: .zero)

        let tile = ConsoleIconTile(symbol: symbol,
                                   size: iconSize,
                                   symbolPointSize: max(16, iconSize * 0.46),
                                   style: .accent)

        subtitleLabel.font = ConsoleTheme.Font.pageSubtitle
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.maximumNumberOfLines = 2
        subtitleLabel.stringValue = subtitle ?? ""
        subtitleLabel.isHidden = (subtitle ?? "").isEmpty

        let textStack = NSStackView(views: [titleLabel, subtitleLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let rowViews: [NSView] = [tile, textStack, spacer] + (accessory.map { [$0] } ?? [])
        let row = NSStackView(views: rowViews)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = ConsoleTheme.Space.sm
        if let accessory {
            accessory.setContentHuggingPriority(.required, for: .horizontal)
            accessory.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            textStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(title: String, subtitle: String?) {
        titleLabel.attributedStringValue = ConsoleTheme.Font.tracked(title,
                                                                     font: ConsoleTheme.Font.pageTitle)
        subtitleLabel.stringValue = subtitle ?? ""
        subtitleLabel.isHidden = (subtitle ?? "").isEmpty
    }
}

/// 空态：图标块 + 标题 + 说明 + 操作按钮。
final class EmptyStateView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(wrappingLabelWithString: "")

    init(symbol: String,
         title: String,
         message: String? = nil,
         actions: [NSButton] = [],
         maxWidth: CGFloat = 360) {
        super.init(frame: .zero)

        let tile = ConsoleIconTile(symbol: symbol, size: 56, symbolPointSize: 24, style: .accent)

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center
        titleLabel.stringValue = title

        messageLabel.font = ConsoleTheme.Font.body
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.alignment = .center
        messageLabel.maximumNumberOfLines = 3
        messageLabel.stringValue = message ?? ""
        messageLabel.isHidden = (message ?? "").isEmpty
        messageLabel.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth).isActive = true

        let actionRow = NSStackView(views: actions)
        actionRow.orientation = .horizontal
        actionRow.spacing = ConsoleTheme.Space.xs
        actionRow.alignment = .centerY
        actionRow.isHidden = actions.isEmpty

        let stack = NSStackView(views: [tile, titleLabel, messageLabel, actionRow])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = ConsoleTheme.Space.sm
        stack.setCustomSpacing(ConsoleTheme.Space.lg, after: tile)
        stack.setCustomSpacing(ConsoleTheme.Space.lg, after: messageLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
            stack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -24),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(title: String, message: String?) {
        titleLabel.stringValue = title
        messageLabel.stringValue = message ?? ""
        messageLabel.isHidden = (message ?? "").isEmpty
    }
}

/// 离线 / 只读等提示条：带图标，不只靠颜色表达。
final class ConsoleNoticeView: NSView {
    enum Tone { case info, warning }

    private let iconView = NSImageView()
    private let label = NSTextField(wrappingLabelWithString: "")
    private let tone: Tone

    init(tone: Tone = .warning) {
        self.tone = tone
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = ConsoleTheme.Radius.control
        layer?.cornerCurve = .continuous

        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 13),
            iconView.heightAnchor.constraint(equalToConstant: 13),
        ])
        iconView.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                                  accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold))

        label.font = .systemFont(ofSize: 11.5, weight: .medium)
        label.maximumNumberOfLines = 2

        let stack = NSStackView(views: [iconView, label])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 7
        stack.edgeInsets = NSEdgeInsets(top: 9, left: 12, bottom: 9, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(text: String) {
        label.stringValue = text
        setAccessibilityLabel(text)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        performWithEffectiveAppearance { [weak self] in
            self?.applyColors()
        }
    }

    private func applyColors() {
        let tint = tone == .warning ? ConsoleTheme.Color.warning : ConsoleTheme.Color.info
        layer?.backgroundColor = tint.withAlphaComponent(0.11).cgColor
        iconView.contentTintColor = tint
        label.textColor = .labelColor
    }
}

/// 信息行：标签 + 值 + 右侧 accessory（模板详情用）。
final class ConsoleInfoRow: NSView {
    private let valueLabel = NSTextField(labelWithString: "")

    init(label: String, value: String, accessory: NSView? = nil) {
        super.init(frame: .zero)

        let keyLabel = NSTextField(labelWithString: label)
        keyLabel.font = .systemFont(ofSize: 11.5)
        keyLabel.textColor = .secondaryLabelColor
        keyLabel.setContentHuggingPriority(.required, for: .horizontal)
        keyLabel.widthAnchor.constraint(equalToConstant: 64).isActive = true

        valueLabel.font = ConsoleTheme.Font.body
        valueLabel.textColor = .labelColor
        valueLabel.lineBreakMode = .byTruncatingMiddle
        valueLabel.toolTip = value
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let rowViews: [NSView] = [keyLabel, valueLabel, spacer] + (accessory.map { [$0] } ?? [])
        let row = NSStackView(views: rowViews)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = ConsoleTheme.Space.xs
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
        ])
        valueLabel.stringValue = value
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(value: String) {
        valueLabel.stringValue = value
        valueLabel.toolTip = value
    }
}

// MARK: - 状态胶囊

/// 状态胶囊：SF Symbol 图标 + 文案，用语义 tone 表达状态。
final class StatusChip: NSView {
    enum Style { case positive, warning, accent, neutral, destructive }

    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var currentText = ""
    private var currentSymbol: String?
    private var currentStyle: Style = .neutral

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 11
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 22).isActive = true

        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.setAccessibilityElement(false)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 10),
            iconView.heightAnchor.constraint(equalToConstant: 10),
        ])

        label.font = ConsoleTheme.Font.chip
        label.lineBreakMode = .byTruncatingTail
        label.setAccessibilityElement(false)

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
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        applyStyle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(text: String, symbol: String? = nil,
                   style: Style, toolTip: String? = nil) {
        currentText = text
        currentSymbol = symbol
        currentStyle = style
        self.toolTip = toolTip
        applyStyle()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        performWithEffectiveAppearance { [weak self] in
            self?.applyStyle()
        }
    }

    private func applyStyle() {
        let tint: NSColor
        switch currentStyle {
        case .positive: tint = ConsoleTheme.Color.positive
        case .warning: tint = ConsoleTheme.Color.warning
        case .accent: tint = ConsoleTheme.Color.accent
        case .destructive: tint = ConsoleTheme.Color.destructive
        case .neutral: tint = .secondaryLabelColor
        }

        label.stringValue = currentText
        label.textColor = currentStyle == .neutral ? .secondaryLabelColor : .labelColor

        let symbol = currentSymbol ?? Self.defaultSymbol(for: currentStyle)
        let configuration = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        iconView.contentTintColor = currentStyle == .neutral ? .tertiaryLabelColor : tint

        layer?.backgroundColor = (currentStyle == .neutral
            ? ConsoleTheme.Color.insetFill
            : tint.withAlphaComponent(0.12)).cgColor

        setAccessibilityLabel(currentText)
    }

    private static func defaultSymbol(for style: Style) -> String {
        switch style {
        case .positive: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .accent: return "circle.fill"
        case .destructive: return "xmark.circle.fill"
        case .neutral: return "circle"
        }
    }
}

// MARK: - 按钮

enum ConsoleButtonStyle {
    case primary
    case secondary
}

/// 统一按钮：主按钮用系统强调色，次按钮保持原生描边。
@discardableResult
func makeConsoleButton(_ title: String,
                       symbol: String? = nil,
                       style: ConsoleButtonStyle = .secondary,
                       controlSize: NSControl.ControlSize = .regular,
                       target: AnyObject?,
                       action: Selector) -> NSButton {
    let button = NSButton(title: title, target: target, action: action)
    button.bezelStyle = .rounded
    button.controlSize = controlSize
    button.font = ConsoleTheme.Font.button
    if let symbol {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .medium))
        button.imagePosition = .imageLeading
    }
    configureConsoleButton(button, title: title, symbol: symbol, style: style)
    return button
}

func configureConsoleButton(_ button: NSButton,
                            title: String,
                            symbol: String?,
                            style: ConsoleButtonStyle) {
    button.title = title
    button.setAccessibilityLabel(title)
    switch style {
    case .primary:
        button.bezelColor = ConsoleTheme.Color.accent
        button.contentTintColor = ConsoleTheme.Color.contrastingLabel(on: ConsoleTheme.Color.accent)
    case .secondary:
        button.bezelColor = nil
        button.contentTintColor = nil
    }
}

/// 图标按钮（无边框），用于"更多"等轻量操作。
func makeIconButton(symbol: String,
                    accessibilityLabel: String,
                    target: AnyObject?,
                    action: Selector) -> NSButton {
    let button = NSButton(image: NSImage(systemSymbolName: symbol,
                                         accessibilityDescription: accessibilityLabel) ?? NSImage(),
                          target: target,
                          action: action)
    button.bezelStyle = .texturedRounded
    button.isBordered = false
    button.imageScaling = .scaleProportionallyDown
    button.setAccessibilityLabel(accessibilityLabel)
    button.toolTip = accessibilityLabel
    button.translatesAutoresizingMaskIntoConstraints = false
    button.widthAnchor.constraint(equalToConstant: 24).isActive = true
    button.heightAnchor.constraint(equalToConstant: 24).isActive = true
    return button
}

// MARK: - 其他通用组件

/// 统一的小号图标按钮（SF Symbols）。
func makeSymbolButton(symbol: String,
                      title: String? = nil,
                      target: AnyObject?,
                      action: Selector,
                      accessibilityLabel: String? = nil) -> NSButton {
    let button = NSButton(title: title ?? "", target: target, action: action)
    button.bezelStyle = .rounded
    button.controlSize = .regular
    button.font = .systemFont(ofSize: 12, weight: .medium)
    button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
    button.imagePosition = title == nil ? .imageOnly : .imageLeading
    if let accessibilityLabel {
        button.setAccessibilityLabel(accessibilityLabel)
    }
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

/// 控制台详情页的滚动容器：内容自上而下排列，留白由参数控制。
/// 文档视图必须与 clip view 同宽且原点为 0，留白由内层 stack 承担，
/// 否则 NSClipView 会把带偏移的文档视图滚到左边缘，左边距变 0。
final class ConsoleScrollPage: NSView {
    let stack = FlippedStackView()
    private let horizontalInset: CGFloat
    private let spacing: CGFloat

    init(horizontalInset: CGFloat = 22, spacing: CGFloat = 14) {
        self.horizontalInset = horizontalInset
        self.spacing = spacing
        super.init(frame: .zero)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func build() {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing

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

            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: horizontalInset),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -horizontalInset),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
        ])
    }
}

/// 小标题：SF Symbol + 文案，用于卡片内分区。
func makeSectionLabel(_ text: String, symbol: String? = nil) -> NSView {
    let label = NSTextField(labelWithString: text)
    label.font = ConsoleTheme.Font.sectionTitle
    label.textColor = .secondaryLabelColor

    guard let symbol,
          let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)) else {
        return label
    }
    let icon = NSImageView(image: image)
    icon.contentTintColor = .secondaryLabelColor
    icon.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        icon.widthAnchor.constraint(equalToConstant: 13),
        icon.heightAnchor.constraint(equalToConstant: 13),
    ])
    let stack = NSStackView(views: [icon, label])
    stack.orientation = .horizontal
    stack.spacing = 5
    stack.alignment = .centerY
    return stack
}
