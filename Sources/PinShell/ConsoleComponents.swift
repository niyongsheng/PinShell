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

/// 页面内标准分组卡片：原生 control 底色 + 发丝线，不投影。内容内缩由 `inset` 控制。
final class ConsoleCard: NSView {
    let contentView = NSView()

    init(cornerRadius: CGFloat = ConsoleTheme.Radius.card,
         inset: NSEdgeInsets = NSEdgeInsets(top: ConsoleTheme.Space.cardInset,
                                           left: ConsoleTheme.Space.cardInset,
                                           bottom: ConsoleTheme.Space.cardInset,
                                           right: ConsoleTheme.Space.cardInset)) {
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
        applySurface()
    }

    /// 动态颜色写入 CGColor 时必须按当前外观解析：视图可能在主题切换后才创建。
    private func applySurface() {
        performWithEffectiveAppearance { [weak self] in
            self?.layer?.backgroundColor = ConsoleTheme.Color.cardFill.cgColor
            self?.layer?.borderColor = ConsoleTheme.Color.cardStroke.cgColor
        }
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
        applySurface()
    }

    private func applySurface() {
        performWithEffectiveAppearance { [weak self] in
            self?.layer?.backgroundColor = ConsoleTheme.Color.insetFill.cgColor
        }
    }
}

/// 预览舞台：柔和渐变底 + 发丝线，让模板像放在摄影棚里。
final class ConsoleStageView: NSView {
    let contentView = NSView()
    private let showsBorder: Bool

    init(cornerRadius: CGFloat = ConsoleTheme.Radius.stage,
         inset: CGFloat = ConsoleTheme.Space.stageInset,
         showsBorder: Bool = true) {
        self.showsBorder = showsBorder
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.borderWidth = showsBorder ? 0.5 : 0
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
        applyBorder()
        needsDisplay = true
    }

    private func applyBorder() {
        guard showsBorder else { return }
        performWithEffectiveAppearance { [weak self] in
            self?.layer?.borderColor = ConsoleTheme.Color.cardStroke.cgColor
        }
    }
}

// MARK: - 空态

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

        let tile = SettingsIconTile(symbol: symbol, tint: ConsoleTheme.Color.accent, size: 40)

        titleLabel.font = ConsoleTheme.Font.emptyTitle
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

        label.font = ConsoleTheme.Font.caption
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
        applyColors()
    }

    private func applyColors() {
        performWithEffectiveAppearance { [weak self] in
            guard let self else { return }
            let tint = tone == .warning ? ConsoleTheme.Color.warning : ConsoleTheme.Color.info
            layer?.backgroundColor = tint.withAlphaComponent(0.11).cgColor
            iconView.contentTintColor = tint
            label.textColor = .labelColor
        }
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
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 20).isActive = true

        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.setAccessibilityElement(false)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 9),
            iconView.heightAnchor.constraint(equalToConstant: 9),
        ])

        label.font = ConsoleTheme.Font.chip
        label.lineBreakMode = .byTruncatingTail
        label.setAccessibilityElement(false)

        let stack = NSStackView(views: [iconView, label])
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 7, bottom: 2, right: 8)
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
        applyStyle()
    }

    private func applyStyle() {
        performWithEffectiveAppearance { [weak self] in
            guard let self else { return }
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
                       action: Selector,
                       tint: NSColor? = nil) -> NSButton {
    // 带 tint 的是关于页的链接式按钮：只保留彩色图标和文字，悬停时铺一层同色淡底。
    let button: NSButton
    if let tint {
        button = ConsoleTintButton(title: title, tint: tint, target: target, action: action)
    } else {
        button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .rounded
    }
    button.controlSize = controlSize
    if let symbol {
        var configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        if let tint {
            configuration = configuration.applying(
                NSImage.SymbolConfiguration(paletteColors: [tint]))
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(configuration)
        button.imagePosition = .imageLeading
    }
    configureConsoleButton(button, title: title, symbol: symbol, style: style)
    return button
}

/// 链接式按钮：图标 + 文字、无描边；悬停时在内容后面铺一层很淡的 tint 圆角底，
/// 指针变手型。底色画在按钮自身 layer 上，位于文字与图标之下。
final class ConsoleTintButton: NSButton {
    private let hoverTint: NSColor
    private var trackingArea: NSTrackingArea?

    private var hovered = false {
        didSet {
            guard hovered != oldValue else { return }
            layer?.backgroundColor = hovered
                ? hoverTint.withAlphaComponent(0.14).cgColor
                : NSColor.clear.cgColor
        }
    }

    init(title: String, tint: NSColor, target: AnyObject?, action: Selector) {
        hoverTint = tint
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        // 默认 NSButton 会把图标和标题分别贴到内容区两端，中间留一大段空；
        // 让标题贴近图标，整组内容居中，悬停底色两侧的内边距才均匀。
        imageHugsTitle = true
        wantsLayer = true
        layer?.cornerRadius = ConsoleTheme.Radius.control
        layer?.cornerCurve = .continuous
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// 给悬停底色留出内边距，圆角才不会贴着图标和文字。
    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: size.width + 16, height: size.height + 8)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
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

/// 22pt 无边框图标按钮的统一外观；也供需要携带额外状态的子类复用。
func configureIconButton(_ button: NSButton,
                         symbol: String,
                         accessibilityLabel: String,
                         pointSize: CGFloat? = nil) {
    var image = NSImage(systemSymbolName: symbol, accessibilityDescription: accessibilityLabel)
    if let pointSize {
        image = image?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular))
    }
    button.image = image ?? NSImage()
    button.bezelStyle = .texturedRounded
    button.isBordered = false
    button.imageScaling = .scaleProportionallyDown
    button.setAccessibilityLabel(accessibilityLabel)
    button.toolTip = accessibilityLabel
    button.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        button.widthAnchor.constraint(equalToConstant: 22),
        button.heightAnchor.constraint(equalToConstant: 22),
    ])
}

/// 延迟复位：重复触发时取消上一次，避免旧回调覆盖新状态。
struct DelayedReset {
    private var work: DispatchWorkItem?

    mutating func schedule(after seconds: TimeInterval, _ action: @escaping () -> Void) {
        work?.cancel()
        let item = DispatchWorkItem(block: action)
        work = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }
}

/// 图标按钮（无边框），用于"更多"等轻量操作。
func makeIconButton(symbol: String,
                    accessibilityLabel: String,
                    target: AnyObject?,
                    action: Selector) -> NSButton {
    let button = NSButton(image: NSImage(), target: target, action: action)
    configureIconButton(button, symbol: symbol, accessibilityLabel: accessibilityLabel)
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

    init(horizontalInset: CGFloat = ConsoleTheme.Space.pageInset,
         spacing: CGFloat = ConsoleTheme.Space.lg) {
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
            stack.topAnchor.constraint(equalTo: document.topAnchor,
                                       constant: ConsoleTheme.Space.lg),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor,
                                          constant: -ConsoleTheme.Space.xl),
        ])
    }
}

extension NSView {
    func pinEdges(to parent: NSView) {
        translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(self)
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            topAnchor.constraint(equalTo: parent.topAnchor),
            bottomAnchor.constraint(equalTo: parent.bottomAnchor),
        ])
    }
}

/// 控制台错误弹窗：模板库卡片与深链安装共用同一套文案与 sheet 行为。
func presentConsoleErrorAlert(_ error: Error, in window: NSWindow?) {
    let alert = NSAlert()
    alert.messageText = NSLocalizedString("library.error.title", comment: "")
    alert.informativeText = error.localizedDescription
    alert.alertStyle = .warning
    alert.addButton(withTitle: NSLocalizedString("console.error.ok", comment: ""))
    if let window {
        alert.beginSheetModal(for: window)
    } else {
        alert.runModal()
    }
}

/// 复制文本到剪贴板；反馈动画由调用方决定。
@discardableResult
func copyStringToPasteboard(_ text: String) -> Bool {
    NSPasteboard.general.clearContents()
    return NSPasteboard.general.setString(text, forType: .string)
}

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
