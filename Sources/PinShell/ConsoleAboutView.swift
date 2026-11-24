import AppKit

/// 控制台「关于」页：品牌信息、联系渠道、支持方式与隐私说明。
final class ConsoleAboutView: NSView {
    private static let websiteURLString = "https://pinshell.looplooptech.com/"
    private static let repositoryURLString = "https://github.com/\(UpdateChecker.repo)"
    private static let issuesURLString = "\(repositoryURLString)/issues"
    private static let sponsorURLString = "https://ifdian.net/a/nico2026"
    private static let emailAddress = "niyongsheng@outlook.com"

    /// 分享面板由系统持有，但窗口关闭前保留引用，避免弹出途中被释放。
    private var sharingPicker: NSSharingServicePicker?

    private lazy var analyticsSwitch: NSSwitch = {
        let toggle = NSSwitch()
        toggle.target = self
        toggle.action = #selector(analyticsToggled(_:))
        toggle.state = Analytics.shared.isEnabled ? .on : .off
        toggle.setAccessibilityLabel(NSLocalizedString("console.about.analytics", comment: ""))
        return toggle
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - 装配

    private func build() {
        let page = ConsoleScrollPage(horizontalInset: ConsoleTheme.Space.pageInset,
                                     spacing: 0)
        page.translatesAutoresizingMaskIntoConstraints = false
        addSubview(page)
        NSLayoutConstraint.activate([
            page.leadingAnchor.constraint(equalTo: leadingAnchor),
            page.trailingAnchor.constraint(equalTo: trailingAnchor),
            page.topAnchor.constraint(equalTo: topAnchor),
            page.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // 居中一列：窗口很宽时内容不铺满，保持阅读宽度。
        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = ConsoleTheme.Space.md
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

        let hero = buildHero()

        let contactHeader = makeSectionLabel(
            NSLocalizedString("console.about.findUs", comment: ""))
        let contactCard = buildContactCard()

        let supportCard = buildSupportCard()
        let feedbackCard = buildFeedbackCard()

        let privacyHeader = makeSectionLabel(
            NSLocalizedString("console.about.privacy", comment: ""))
        let analyticsCard = buildAnalyticsCard()

        let footer = buildFooter()

        let sections: [(view: NSView, spacingAfter: CGFloat)] = [
            (hero, ConsoleTheme.Space.xl),
            (contactHeader, ConsoleTheme.Space.xs),
            (contactCard, ConsoleTheme.Space.lg),
            (supportCard, ConsoleTheme.Space.sm),
            (feedbackCard, ConsoleTheme.Space.xl),
            (privacyHeader, ConsoleTheme.Space.xs),
            (analyticsCard, ConsoleTheme.Space.lg),
            (footer, 0),
        ]
        for (index, section) in sections.enumerated() {
            column.addArrangedSubview(section.view)
            section.view.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
            if index < sections.count - 1 {
                column.setCustomSpacing(section.spacingAfter, after: section.view)
            }
        }
    }

    private func buildHero() -> NSView {
        let icon = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 72),
            icon.heightAnchor.constraint(equalToConstant: 72),
        ])

        let title = NSTextField(labelWithAttributedString:
            ConsoleTheme.Font.tracked("PinShell",
                                      font: .systemFont(ofSize: 26, weight: .semibold),
                                      tracking: -0.4))

        let version = NSTextField(labelWithString: String(
            format: NSLocalizedString("console.about.version", comment: ""),
            UpdateChecker.currentVersion))
        version.font = .systemFont(ofSize: 11.5)
        version.textColor = .secondaryLabelColor

        let subtitle = NSTextField(wrappingLabelWithString:
            NSLocalizedString("console.about.subtitle", comment: ""))
        subtitle.font = .systemFont(ofSize: 12.5)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center
        subtitle.maximumNumberOfLines = 3
        subtitle.widthAnchor.constraint(lessThanOrEqualToConstant: 460).isActive = true

        let stack = NSStackView(views: [icon, title, version, subtitle])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 5
        stack.setCustomSpacing(12, after: icon)
        stack.setCustomSpacing(10, after: version)
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 4, right: 0)
        return stack
    }

    // MARK: - 分区

    private func buildContactCard() -> NSView {
        let rowHint = NSLocalizedString("console.about.rowHint", comment: "")
        let website = AboutRow(
            title: NSLocalizedString("console.about.website", comment: ""),
            value: Self.websiteURLString,
            copyTitle: NSLocalizedString("console.about.copyLink", comment: ""),
            toolTip: rowHint,
            action: { [weak self] in self?.open(Self.websiteURLString) })

        let github = AboutRow(
            title: NSLocalizedString("console.about.github", comment: ""),
            value: "github.com/\(UpdateChecker.repo)",
            copyTitle: NSLocalizedString("console.about.copyLink", comment: ""),
            toolTip: rowHint,
            action: { [weak self] in self?.open(Self.repositoryURLString) })

        let email = AboutRow(
            title: NSLocalizedString("console.about.email", comment: ""),
            value: Self.emailAddress,
            copyTitle: NSLocalizedString("console.about.copyEmail", comment: ""),
            toolTip: rowHint,
            action: { [weak self] in self?.open("mailto:\(Self.emailAddress)") })

        return makeGroupedCard(rows: [website, github, email])
    }

    private func buildSupportCard() -> NSView {
        let card = ConsoleCard(inset: NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20))
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: card.contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor),
        ])

        let message = NSTextField(wrappingLabelWithString:
            NSLocalizedString("console.about.supportText", comment: ""))
        message.font = ConsoleTheme.Font.body
        message.textColor = .labelColor
        message.maximumNumberOfLines = 4
        stack.addArrangedSubview(message)
        message.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let share = makeConsoleButton(
            NSLocalizedString("console.about.share", comment: ""),
            symbol: "square.and.arrow.up",
            target: self,
            action: #selector(shareTapped(_:)),
            tint: ConsoleTheme.Color.positive)

        let star = makeConsoleButton(
            NSLocalizedString("console.about.star", comment: ""),
            symbol: "star.fill",
            target: self,
            action: #selector(openRepository),
            tint: .systemYellow)

        let sponsor = makeConsoleButton(
            NSLocalizedString("console.about.sponsor", comment: ""),
            symbol: "heart.fill",
            target: self,
            action: #selector(openSponsor),
            tint: ConsoleTheme.Color.brandRed)

        let buttons = NSStackView(views: [sponsor, star, share])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = ConsoleTheme.Space.xs
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let centered = NSView()
        centered.addSubview(buttons)
        NSLayoutConstraint.activate([
            buttons.centerXAnchor.constraint(equalTo: centered.centerXAnchor),
            buttons.topAnchor.constraint(equalTo: centered.topAnchor),
            buttons.bottomAnchor.constraint(equalTo: centered.bottomAnchor),
            buttons.leadingAnchor.constraint(greaterThanOrEqualTo: centered.leadingAnchor),
            buttons.trailingAnchor.constraint(lessThanOrEqualTo: centered.trailingAnchor),
        ])
        stack.addArrangedSubview(centered)
        centered.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        return card
    }

    private func buildFeedbackCard() -> NSView {
        let feedback = AboutRow(
            title: NSLocalizedString("console.about.feedback", comment: ""),
            disclosure: true,
            toolTip: NSLocalizedString("console.about.feedbackHint", comment: ""),
            action: { [weak self] in self?.open(Self.issuesURLString) })
        return makeGroupedCard(rows: [feedback])
    }

    /// 隐私设置 cell：说明文字 + 右侧开关。
    private func buildAnalyticsCard() -> NSView {
        let card = ConsoleCard(inset: NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0))

        let text = NSTextField(wrappingLabelWithString:
            NSLocalizedString("console.about.privacyText", comment: ""))
        text.font = ConsoleTheme.Font.caption
        text.textColor = .secondaryLabelColor
        text.maximumNumberOfLines = 2
        text.lineBreakMode = .byWordWrapping
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        analyticsSwitch.setContentHuggingPriority(.required, for: .horizontal)
        analyticsSwitch.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = NSStackView(views: [text, spacer, analyticsSwitch])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        row.translatesAutoresizingMaskIntoConstraints = false

        card.contentView.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor),
            row.topAnchor.constraint(equalTo: card.contentView.topAnchor),
            row.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor),
        ])
        return card
    }

    private func buildFooter() -> NSView {
        let label = NSTextField(labelWithString:
            NSLocalizedString("console.about.copyright", comment: ""))
        label.font = ConsoleTheme.Font.micro
        label.textColor = .tertiaryLabelColor
        label.alignment = .center
        return label
    }

    /// 无内缩卡片 + 行间发丝线，行内留白由 AboutRow 自己承担。
    private func makeGroupedCard(rows: [NSView]) -> NSView {
        let card = ConsoleCard(inset: NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0))
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: card.contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor),
        ])

        for (index, row) in rows.enumerated() {
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            if index < rows.count - 1 {
                let divider = HairlineView()
                stack.addArrangedSubview(divider)
                divider.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
        }
        return card
    }

    // MARK: - 动作

    @objc private func shareTapped(_ sender: NSButton) {
        guard let url = URL(string: Self.websiteURLString) else { return }
        let picker = NSSharingServicePicker(items: [url])
        sharingPicker = picker
        picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }

    @objc private func openRepository() {
        open(Self.repositoryURLString)
    }

    @objc private func openSponsor() {
        open(Self.sponsorURLString)
    }

    @objc private func analyticsToggled(_ sender: NSSwitch) {
        Analytics.shared.isEnabled = sender.state == .on
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - 分组行

/// 关于页的分组行：左标题、右值（链接色）；左键打开，右键复制。
private final class AboutRow: NSView {
    private let valueLabel = NSTextField(labelWithString: "")
    private let highlightView = NSView()
    private let valueText: String?
    private let copyValue: String?
    private let handler: () -> Void
    private var trackingArea: NSTrackingArea?
    private var copyResetWork: DispatchWorkItem?

    private var hovered = false {
        didSet { highlightView.isHidden = !hovered }
    }

    init(title: String,
         value: String? = nil,
         disclosure: Bool = false,
         copyValue: String? = nil,
         copyTitle: String? = nil,
         toolTip: String? = nil,
         action: @escaping () -> Void) {
        self.valueText = value
        // 可复制内容默认就是展示值；只有需要复制完整 URL 之类的情况下才单独指定。
        self.copyValue = copyValue ?? value
        self.handler = action
        super.init(frame: .zero)

        highlightView.wantsLayer = true
        highlightView.layer?.cornerRadius = 8
        highlightView.layer?.cornerCurve = .continuous
        highlightView.isHidden = true
        highlightView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(highlightView)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)

        valueLabel.stringValue = value ?? ""
        valueLabel.font = .systemFont(ofSize: 12.5)
        valueLabel.textColor = ConsoleTheme.Color.accent
        valueLabel.alignment = .right
        valueLabel.lineBreakMode = .byTruncatingMiddle
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        valueLabel.isHidden = value == nil

        let chevronImage = NSImage(systemSymbolName: "chevron.right",
                                   accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10,
                                                                 weight: .semibold))
        let chevron = NSImageView(image: chevronImage ?? NSImage())
        chevron.contentTintColor = .tertiaryLabelColor
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.isHidden = !disclosure
        NSLayoutConstraint.activate([
            chevron.widthAnchor.constraint(equalToConstant: 7),
            chevron.heightAnchor.constraint(equalToConstant: 12),
        ])

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [titleLabel, spacer, valueLabel, chevron])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = ConsoleTheme.Space.xs
        row.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 14)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            highlightView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            highlightView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            highlightView.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            highlightView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),

            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])

        self.toolTip = toolTip
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        if let value {
            setAccessibilityValue(value)
        }
        if let toolTip {
            setAccessibilityHelp(toolTip)
        }
        if let copyValue, let copyTitle {
            // 辅助功能用户无法右键，补一个“复制链接”自定义动作。
            let copyAction = NSAccessibilityCustomAction(name: copyTitle) { [weak self] in
                self?.copyToPasteboard(copyValue) ?? false
            }
            setAccessibilityCustomActions([copyAction])
        }

        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(clicked(_:))))
        applyHighlightColor()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func clicked(_ sender: NSClickGestureRecognizer) {
        handler()
    }

    override func accessibilityPerformPress() -> Bool {
        handler()
        return true
    }

    // MARK: 悬停

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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        performWithEffectiveAppearance { [weak self] in
            self?.applyHighlightColor()
        }
    }

    private func applyHighlightColor() {
        highlightView.layer?.backgroundColor = ConsoleTheme.Color.insetFill.cgColor
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
        copyResetWork?.cancel()
        valueLabel.stringValue = NSLocalizedString("console.about.copied", comment: "")
        valueLabel.textColor = ConsoleTheme.Color.positive
        let work = DispatchWorkItem { [weak self] in
            self?.valueLabel.stringValue = valueText
            self?.valueLabel.textColor = ConsoleTheme.Color.accent
        }
        copyResetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }
}
