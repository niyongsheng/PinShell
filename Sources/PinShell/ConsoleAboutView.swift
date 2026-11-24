import AppKit

/// 控制台「关于」页：品牌信息、联系渠道与支持方式。
final class ConsoleAboutView: NSView, ConsoleServicePage {
    private static let websiteURLString = "https://pinshell.looplooptech.com/"
    private static let repositoryURLString = "https://github.com/\(UpdateChecker.repo)"
    private static let issuesURLString = "\(repositoryURLString)/issues"
    private static let sponsorURLString = "https://ifdian.net/a/nico2026"
    private static let emailAddress = "niyongsheng@outlook.com"

    /// 分享面板由系统持有，但窗口关闭前保留引用，避免弹出途中被释放。
    private var sharingPicker: NSSharingServicePicker?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - 装配

    private func build() {
        let page = SettingsPageView(spacing: ConsoleTheme.Space.md)
        page.pinEdges(to: self)

        let hero = buildHero()

        let contactHeader = makeSectionLabel(
            NSLocalizedString("console.about.findUs", comment: ""))
        let contactCard = buildContactCard()

        let supportCard = buildSupportCard()
        let feedbackCard = buildFeedbackCard()

        let footer = buildFooter()

        let sections: [(view: NSView, spacingAfter: CGFloat)] = [
            (hero, ConsoleTheme.Space.xl),
            (contactHeader, ConsoleTheme.Space.xs),
            (contactCard, ConsoleTheme.Space.lg),
            (supportCard, ConsoleTheme.Space.sm),
            (feedbackCard, ConsoleTheme.Space.xl),
            (footer, 0),
        ]
        for (index, section) in sections.enumerated() {
            page.addSection(section.view)
            if index < sections.count - 1 {
                page.column.setCustomSpacing(section.spacingAfter, after: section.view)
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
            ConsoleTheme.Font.tracked("PinShell", font: ConsoleTheme.Font.pageTitle))

        let version = NSTextField(labelWithString: String(
            format: NSLocalizedString("console.about.version", comment: ""),
            UpdateChecker.currentVersion))
        version.font = ConsoleTheme.Font.caption
        version.textColor = .secondaryLabelColor

        let subtitle = NSTextField(wrappingLabelWithString:
            NSLocalizedString("console.about.subtitle", comment: ""))
        subtitle.font = ConsoleTheme.Font.pageSubtitle
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
        let rows = [
            makeLinkRow(title: NSLocalizedString("console.about.website", comment: ""),
                        value: Self.websiteURLString,
                        copyTitle: NSLocalizedString("console.about.copyLink", comment: ""),
                        toolTip: rowHint,
                        urlString: Self.websiteURLString),
            makeLinkRow(title: NSLocalizedString("console.about.github", comment: ""),
                        value: "github.com/\(UpdateChecker.repo)",
                        copyTitle: NSLocalizedString("console.about.copyLink", comment: ""),
                        toolTip: rowHint,
                        urlString: Self.repositoryURLString),
            makeLinkRow(title: NSLocalizedString("console.about.email", comment: ""),
                        value: Self.emailAddress,
                        copyTitle: NSLocalizedString("console.about.copyEmail", comment: ""),
                        toolTip: rowHint,
                        urlString: "mailto:\(Self.emailAddress)"),
        ]
        return makeGroupedCard(rows: rows)
    }

    /// 关于页链接行：左键打开、右键复制。
    private func makeLinkRow(title: String,
                             value: String,
                             copyTitle: String,
                             toolTip: String,
                             urlString: String) -> NSView {
        let row = SettingsRowView(
            title: title,
            value: value,
            valueColor: ConsoleTheme.Color.accent,
            showsChevron: true,
            copyValue: value,
            copyTitle: copyTitle,
            onClick: { [weak self] in self?.open(urlString) })
        row.toolTip = toolTip
        row.setAccessibilityHelp(toolTip)
        return row
    }

    private func buildSupportCard() -> NSView {
        let card = ConsoleCard(inset: NSEdgeInsets(top: ConsoleTheme.Space.cardInset,
                                                   left: ConsoleTheme.Space.cardInset,
                                                   bottom: ConsoleTheme.Space.cardInset,
                                                   right: ConsoleTheme.Space.cardInset))
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
        message.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(message)
        message.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let share = makeConsoleButton(
            NSLocalizedString("console.about.share", comment: ""),
            symbol: "square.and.arrow.up",
            target: self,
            action: #selector(shareTapped(_:)),
            tint: ConsoleTheme.Color.trafficGreen)

        let star = makeConsoleButton(
            NSLocalizedString("console.about.star", comment: ""),
            symbol: "star.fill",
            target: self,
            action: #selector(openRepository),
            tint: ConsoleTheme.Color.trafficYellow)

        let sponsor = makeConsoleButton(
            NSLocalizedString("console.about.sponsor", comment: ""),
            symbol: "heart.fill",
            target: self,
            action: #selector(openSponsor),
            tint: ConsoleTheme.Color.trafficRed)

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
        let hint = NSLocalizedString("console.about.feedbackHint", comment: "")
        let feedback = SettingsRowView(
            title: NSLocalizedString("console.about.feedback", comment: ""),
            showsChevron: true,
            onClick: { [weak self] in self?.open(Self.issuesURLString) })
        feedback.toolTip = hint
        feedback.setAccessibilityHelp(hint)
        return makeGroupedCard(rows: [feedback])
    }

    private func buildFooter() -> NSView {
        let label = NSTextField(labelWithString:
            NSLocalizedString("console.about.copyright", comment: ""))
        label.font = ConsoleTheme.Font.caption
        label.textColor = .tertiaryLabelColor
        label.alignment = .center
        return label
    }

    /// 无内缩分组卡片：行内留白与行间 16pt 内缩分隔线由 SettingsGroupView 负责。
    private func makeGroupedCard(rows: [NSView]) -> NSView {
        let group = SettingsGroupView()
        for row in rows {
            group.addRow(row)
        }
        return group
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

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
