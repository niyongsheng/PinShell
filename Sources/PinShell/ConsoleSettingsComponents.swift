import AppKit

// MARK: - 页面底色

/// 不透明页面底色：替代整窗 vibrancy，让侧边栏保留材质、内容区保持原生 Settings 观感。
final class ConsoleBackgroundView: NSView {
    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        ConsoleTheme.Color.pageBackground.setFill()
        dirtyRect.fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

// MARK: - 彩色图标块

/// 系统设置式彩色圆角图标块：实心系统色 + 白色 SF Symbol。
final class SettingsIconTile: NSView {
    private let imageView = NSImageView()
    private let tileSize: CGFloat
    private let tint: NSColor

    init(symbol: String, tint: NSColor, size: CGFloat = 20) {
        tileSize = size
        self.tint = tint
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = max(4, min(9, size * 0.26))
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: size).isActive = true
        heightAnchor.constraint(equalToConstant: size).isActive = true

        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = .white
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        applyTint()
        setSymbol(symbol)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTint()
    }

    private func applyTint() {
        performWithEffectiveAppearance { [weak self] in
            self?.layer?.backgroundColor = self?.tint.cgColor
        }
    }

    private func setSymbol(_ name: String) {
        let pointSize = max(10, tileSize * 0.54)
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        imageView.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }
}

// MARK: - 页头

/// Settings 式页头：22pt 标题 + 13pt 副标题，无装饰图标块。
final class SettingsPageHeaderView: NSView {
    private let titleLabel: NSTextField
    private let subtitleLabel = NSTextField(wrappingLabelWithString: "")

    init(title: String, subtitle: String? = nil, accessory: NSView? = nil) {
        titleLabel = NSTextField(labelWithAttributedString:
            ConsoleTheme.Font.tracked(title, font: ConsoleTheme.Font.pageTitle))
        super.init(frame: .zero)

        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1

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

        var rowViews: [NSView] = [textStack, spacer]
        if let accessory {
            accessory.setContentHuggingPriority(.required, for: .horizontal)
            accessory.setContentCompressionResistancePriority(.required, for: .horizontal)
            rowViews.append(accessory)
        }

        let row = NSStackView(views: rowViews)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = ConsoleTheme.Space.sm
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
}

extension SettingsPageHeaderView {
    /// 服务页通用页头：标题 / 副标题 + 绿色就绪徽标。
    static func ready(titleKey: String, subtitleKey: String, readyKey: String) -> SettingsPageHeaderView {
        let chip = StatusChip()
        chip.configure(text: NSLocalizedString(readyKey, comment: ""),
                       symbol: "checkmark.circle.fill",
                       style: .positive)
        return SettingsPageHeaderView(title: NSLocalizedString(titleKey, comment: ""),
                                      subtitle: NSLocalizedString(subtitleKey, comment: ""),
                                      accessory: chip)
    }
}

// MARK: - 页面容器

/// 设置式页面：滚动容器 + 居中 640pt 列，页面只负责添加分组。
final class SettingsPageView: NSView {
    /// 居中列：需要自定义分组间距时直接操作它。
    let column = NSStackView()

    init(spacing: CGFloat) {
        super.init(frame: .zero)

        let page = ConsoleScrollPage(horizontalInset: ConsoleTheme.Space.pageInset,
                                     spacing: 0)
        page.pinEdges(to: self)

        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = spacing
        column.edgeInsets = NSEdgeInsets(top: 12, left: 0, bottom: 24, right: 0)
        column.translatesAutoresizingMaskIntoConstraints = false
        page.stack.addArrangedSubview(column)
        NSLayoutConstraint.activate([
            column.centerXAnchor.constraint(equalTo: page.stack.centerXAnchor),
            column.widthAnchor.constraint(lessThanOrEqualToConstant: 640),
        ])
        let fillWidth = column.widthAnchor.constraint(equalTo: page.stack.widthAnchor)
        fillWidth.priority = .defaultHigh
        fillWidth.isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func addSection(_ view: NSView) {
        column.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
    }
}

// MARK: - 分组内容

/// 分组内容栈：行、分隔线与自定义内容共用的堆叠容器。
final class SettingsRowsView: NSStackView {
    /// 行槽位：隐藏行时同步隐藏它前面的分隔线。
    final class RowSlot {
        fileprivate let row: NSView
        fileprivate let separator: SettingsSeparatorView?
        fileprivate let onHiddenChange: () -> Void

        fileprivate init(row: NSView,
                         separator: SettingsSeparatorView?,
                         onHiddenChange: @escaping () -> Void) {
            self.row = row
            self.separator = separator
            self.onHiddenChange = onHiddenChange
        }

        func setHidden(_ hidden: Bool) {
            row.isHidden = hidden
            separator?.isHidden = hidden
            onHiddenChange()
        }

        var isHidden: Bool { row.isHidden }
    }

    /// 行隐藏后由所属分组刷新固有尺寸。
    var onHiddenChange: (() -> Void)?

    private var rowCount = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        orientation = .vertical
        alignment = .leading
        spacing = 0
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// 顶部无行的分隔线（如折叠分组的头部与内容之间）。
    func addSeparator() {
        let separator = SettingsSeparatorView()
        addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
    }

    @discardableResult
    func addRow(_ row: NSView) -> RowSlot {
        row.translatesAutoresizingMaskIntoConstraints = false
        var separator: SettingsSeparatorView?
        if rowCount > 0 {
            let line = SettingsSeparatorView()
            addArrangedSubview(line)
            line.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
            separator = line
        }
        addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        rowCount += 1
        return RowSlot(row: row, separator: separator,
                       onHiddenChange: { [weak self] in self?.onHiddenChange?() })
    }

    func addContent(_ view: NSView, insets: NSEdgeInsets = NSEdgeInsets(top: 12, left: 16,
                                                                        bottom: 12, right: 16)) {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: insets.left),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -insets.right),
            view.topAnchor.constraint(equalTo: container.topAnchor, constant: insets.top),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -insets.bottom),
        ])
        addArrangedSubview(container)
        container.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        rowCount += 1
    }
}

// MARK: - 分组卡片

/// 系统设置式分组：可选组标题 + 10pt 圆角卡片 + 16pt 内缩分隔线 + 可选组脚注。
final class SettingsGroupView: NSView {
    private let outerStack = NSStackView()
    private let card = ConsoleCard(inset: NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0))
    private let rows = SettingsRowsView()

    init(title: String? = nil, footer: String? = nil) {
        super.init(frame: .zero)
        rows.onHiddenChange = { [weak self] in self?.invalidateIntrinsicContentSize() }
        build(title: title, footer: footer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func build(title: String?, footer: String?) {
        outerStack.orientation = .vertical
        outerStack.alignment = .leading
        outerStack.spacing = ConsoleTheme.Space.groupHeaderGap
        outerStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(outerStack)
        NSLayoutConstraint.activate([
            outerStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            outerStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            outerStack.topAnchor.constraint(equalTo: topAnchor),
            outerStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        if let title, !title.isEmpty {
            let header = NSTextField(labelWithString: title)
            header.font = ConsoleTheme.Font.sectionTitle
            header.textColor = .secondaryLabelColor
            outerStack.addArrangedSubview(header)
            header.widthAnchor.constraint(equalTo: outerStack.widthAnchor).isActive = true
        }

        card.contentView.addSubview(rows)
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor),
            rows.topAnchor.constraint(equalTo: card.contentView.topAnchor),
            rows.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor),
        ])
        outerStack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: outerStack.widthAnchor).isActive = true

        if let footer, !footer.isEmpty {
            let footerLabel = NSTextField(wrappingLabelWithString: footer)
            footerLabel.font = ConsoleTheme.Font.caption
            footerLabel.textColor = .secondaryLabelColor
            outerStack.addArrangedSubview(footerLabel)
            footerLabel.widthAnchor.constraint(equalTo: outerStack.widthAnchor).isActive = true
            outerStack.setCustomSpacing(6, after: card)
        }
    }

    @discardableResult
    func addRow(_ row: NSView) -> SettingsRowsView.RowSlot {
        rows.addRow(row)
    }

    func addContent(_ view: NSView, insets: NSEdgeInsets = NSEdgeInsets(top: 12, left: 16,
                                                                        bottom: 12, right: 16)) {
        rows.addContent(view, insets: insets)
    }
}

/// 分组内分隔线：1pt，默认左右 16pt 内缩。
final class SettingsSeparatorView: NSView {
    private let line = NSView()

    init(inset: CGFloat = ConsoleTheme.Space.rowInset) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 1).isActive = true

        line.wantsLayer = true
        line.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            line.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            line.topAnchor.constraint(equalTo: topAnchor),
            line.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        applyColor()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColor()
    }

    private func applyColor() {
        performWithEffectiveAppearance { [weak self] in
            self?.line.layer?.backgroundColor = ConsoleTheme.Color.cardStroke.cgColor
        }
    }
}

// MARK: - 分组行

/// 系统设置式分组行：标题 / 副标题 / 右侧值 / accessory，可选点击。
final class SettingsRowView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(wrappingLabelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let onClick: (() -> Void)?
    private var valueText: String?
    private let valueColor: NSColor
    private let copyValue: String?
    private var copyReset = DelayedReset()

    init(title: String,
         subtitle: String? = nil,
         value: String? = nil,
         valueColor: NSColor = .secondaryLabelColor,
         leading: NSView? = nil,
         accessory: NSView? = nil,
         showsChevron: Bool = false,
         copyValue: String? = nil,
         copyTitle: String? = nil,
         onClick: (() -> Void)? = nil) {
        self.onClick = onClick
        self.valueText = value
        self.valueColor = valueColor
        self.copyValue = copyValue
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = ConsoleTheme.Font.rowTitle
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.stringValue = title
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        subtitleLabel.font = ConsoleTheme.Font.caption
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.maximumNumberOfLines = 2
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.stringValue = subtitle ?? ""
        subtitleLabel.isHidden = (subtitle ?? "").isEmpty

        let textStack = NSStackView(views: [titleLabel, subtitleLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        valueLabel.font = ConsoleTheme.Font.body
        valueLabel.textColor = valueColor
        valueLabel.alignment = .right
        valueLabel.lineBreakMode = .byTruncatingMiddle
        valueLabel.stringValue = value ?? ""
        valueLabel.isHidden = value == nil
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let chevron: NSImageView? = showsChevron ? {
            let image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11,
                                                                     weight: .semibold))
            let view = NSImageView(image: image ?? NSImage())
            view.contentTintColor = .tertiaryLabelColor
            view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                view.widthAnchor.constraint(equalToConstant: 8),
                view.heightAnchor.constraint(equalToConstant: 12),
            ])
            return view
        }() : nil

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        var rowViews: [NSView] = []
        if let leading {
            leading.setContentHuggingPriority(.required, for: .horizontal)
            leading.setContentCompressionResistancePriority(.required, for: .horizontal)
            rowViews.append(leading)
        }
        rowViews.append(contentsOf: [textStack, spacer, valueLabel])
        if let accessory {
            accessory.setContentHuggingPriority(.required, for: .horizontal)
            accessory.setContentCompressionResistancePriority(.required, for: .horizontal)
            rowViews.append(accessory)
        }
        if let chevron {
            rowViews.append(chevron)
        }

        let row = NSStackView(views: rowViews)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 8, left: ConsoleTheme.Space.rowInset,
                                      bottom: 8, right: ConsoleTheme.Space.rowInset)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: ConsoleTheme.Space.rowHeight),
        ])

        if onClick != nil {
            setAccessibilityElement(true)
            setAccessibilityRole(.button)
            setAccessibilityLabel(title)
            if let value { setAccessibilityValue(value) }
            addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(clicked(_:))))
        } else {
            setAccessibilityElement(false)
        }

        if let copyValue, let copyTitle {
            // 辅助功能用户无法右键，补一个“复制”自定义动作。
            let copyAction = NSAccessibilityCustomAction(name: copyTitle) { [weak self] in
                self?.copyToPasteboard(copyValue) ?? false
            }
            setAccessibilityCustomActions([copyAction])
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(value: String) {
        valueText = value
        valueLabel.stringValue = value
        valueLabel.isHidden = false
        setAccessibilityValue(value)
    }

    @objc private func clicked(_ sender: NSClickGestureRecognizer) {
        onClick?()
    }

    // MARK: 右键复制

    override func rightMouseDown(with event: NSEvent) {
        guard let copyValue else {
            super.rightMouseDown(with: event)
            return
        }
        copyToPasteboard(copyValue)
    }

    @discardableResult
    private func copyToPasteboard(_ value: String) -> Bool {
        guard copyStringToPasteboard(value) else { return false }
        showCopiedFeedback()
        return true
    }

    private func showCopiedFeedback() {
        guard let valueText else { return }
        valueLabel.stringValue = NSLocalizedString("console.about.copied", comment: "")
        valueLabel.textColor = ConsoleTheme.Color.positive
        copyReset.schedule(after: 1.2) { [weak self] in
            guard let self else { return }
            self.valueLabel.stringValue = valueText
            self.valueLabel.textColor = self.valueColor
        }
    }

    override func accessibilityPerformPress() -> Bool {
        guard let onClick else { return false }
        onClick()
        return true
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard onClick != nil else { return }
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

// MARK: - 折叠分组

/// 系统设置式可折叠分组：44pt 头部 + 分组行；保留展开/收起语义。
final class SettingsDisclosureGroupView: NSView {
    private let card = ConsoleCard(inset: NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0))
    private let headerRow = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    private let chevronButton = NSButton()
    private let contentStack = SettingsRowsView()

    private(set) var isExpanded: Bool

    init(title: String,
         count: Int? = nil,
         accessories: [NSView] = [],
         initiallyExpanded: Bool = false) {
        isExpanded = initiallyExpanded
        super.init(frame: .zero)
        build(title: title, count: count, accessories: accessories)
        applyExpanded(animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func build(title: String, count: Int?, accessories: [NSView]) {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = ConsoleTheme.Font.sectionTitle
        titleLabel.textColor = .labelColor
        titleLabel.stringValue = title
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)

        countLabel.font = ConsoleTheme.Font.caption
        countLabel.textColor = .secondaryLabelColor
        countLabel.stringValue = count.map { "\($0)" } ?? ""
        countLabel.isHidden = count == nil

        chevronButton.isBordered = false
        chevronButton.bezelStyle = .inline
        chevronButton.target = self
        chevronButton.action = #selector(toggle)
        chevronButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            chevronButton.widthAnchor.constraint(equalToConstant: 16),
            chevronButton.heightAnchor.constraint(equalToConstant: 16),
        ])
        updateChevron()

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        var headerViews: [NSView] = [chevronButton, titleLabel, countLabel, spacer]
        headerViews.append(contentsOf: accessories.filter { $0 !== chevronButton })
        let headerStack = NSStackView(views: headerViews)
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.spacing = 8
        headerStack.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addSubview(headerStack)
        NSLayoutConstraint.activate([
            headerStack.leadingAnchor.constraint(equalTo: headerRow.leadingAnchor),
            headerStack.trailingAnchor.constraint(equalTo: headerRow.trailingAnchor),
            headerStack.topAnchor.constraint(equalTo: headerRow.topAnchor),
            headerStack.bottomAnchor.constraint(equalTo: headerRow.bottomAnchor),
            headerRow.heightAnchor.constraint(greaterThanOrEqualToConstant: ConsoleTheme.Space.rowHeight),
        ])
        for accessory in accessories {
            accessory.setContentHuggingPriority(.required, for: .horizontal)
            accessory.setContentCompressionResistancePriority(.required, for: .horizontal)
        }

        let cardStack = NSStackView(views: [headerRow, contentStack])
        cardStack.orientation = .vertical
        cardStack.alignment = .leading
        cardStack.spacing = 0
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        card.contentView.addSubview(cardStack)
        NSLayoutConstraint.activate([
            cardStack.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor),
            cardStack.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor),
            cardStack.topAnchor.constraint(equalTo: card.contentView.topAnchor),
            cardStack.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor),
            headerRow.widthAnchor.constraint(equalTo: cardStack.widthAnchor),
            contentStack.widthAnchor.constraint(equalTo: cardStack.widthAnchor),
        ])

        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        contentStack.addSeparator()
    }

    func addRow(_ row: NSView) {
        contentStack.addRow(row)
    }

    func addContent(_ view: NSView, insets: NSEdgeInsets = NSEdgeInsets(top: 12, left: 16,
                                                                        bottom: 12, right: 16)) {
        contentStack.addContent(view, insets: insets)
    }

    @objc private func toggle() {
        setExpanded(!isExpanded)
    }

    func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        isExpanded = expanded
        applyExpanded(animated: true)
    }

    private func applyExpanded(animated: Bool) {
        updateChevron()
        let hidden = !isExpanded
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                contentStack.animator().isHidden = hidden
            }
        } else {
            contentStack.isHidden = hidden
        }
        let hint = NSLocalizedString(isExpanded ? "console.mcp.collapse" : "console.mcp.expand",
                                     comment: "")
        chevronButton.toolTip = hint
        chevronButton.setAccessibilityLabel(hint)
    }

    private func updateChevron() {
        let name = isExpanded ? "chevron.down" : "chevron.right"
        chevronButton.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold))
        chevronButton.contentTintColor = .secondaryLabelColor
    }
}

// MARK: - 编辑器表单行

/// 编辑器分组表单行：inline（label 左、控件右）或 stacked（label 上、控件占满）。
final class SettingsFormRowView: NSView {
    init(label: String, control: NSView, stretch: Bool = false) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let labelView = NSTextField(labelWithString: label)
        labelView.font = ConsoleTheme.Font.rowTitle
        labelView.textColor = .labelColor
        labelView.lineBreakMode = .byTruncatingTail
        labelView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.setAccessibilityLabel(label)

        let container: NSView
        if stretch {
            labelView.alignment = .left
            let stack = NSStackView(views: [labelView, control])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 6
            control.translatesAutoresizingMaskIntoConstraints = false
            control.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            container = stack
        } else {
            let spacer = NSView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            let stack = NSStackView(views: [labelView, spacer, control])
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 10
            labelView.widthAnchor.constraint(equalToConstant: 88).isActive = true
            container = stack
        }

        container.translatesAutoresizingMaskIntoConstraints = false
        addSubview(container)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: leadingAnchor,
                                               constant: ConsoleTheme.Space.rowInset),
            container.trailingAnchor.constraint(equalTo: trailingAnchor,
                                                constant: -ConsoleTheme.Space.rowInset),
            container.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            container.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            heightAnchor.constraint(greaterThanOrEqualToConstant: ConsoleTheme.Space.formRowHeight),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
