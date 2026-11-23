import AppKit

/// 控制台「关于」页：居中的极简应用信息卡。
final class ConsoleAboutView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - 装配

    private func build() {
        let card = GlassCard(cornerRadius: 20)
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        let icon = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 64),
            icon.heightAnchor.constraint(equalToConstant: 64),
        ])

        let title = NSTextField(labelWithString: "PinShell")
        title.font = .systemFont(ofSize: 24, weight: .semibold)

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

        let afdian = makeLinkButton(
            NSLocalizedString("console.about.afdian", comment: ""),
            symbol: "heart.fill",
            tint: NSColor(srgbRed: 0.58, green: 0.42, blue: 0.90, alpha: 1),
            action: #selector(openAfdian))

        let links = NSStackView(views: [
            afdian,
            makeLinkButton(NSLocalizedString("console.about.website", comment: ""),
                           symbol: "globe",
                           tint: .controlAccentColor,
                           action: #selector(openWebsite)),
            makeLinkButton(NSLocalizedString("console.about.github", comment: ""),
                           symbol: "chevron.left.forwardslash.chevron.right",
                           tint: .labelColor,
                           action: #selector(openRepository)),
        ])
        links.orientation = .horizontal
        links.spacing = 8
        links.alignment = .centerY

        let copyright = NSTextField(labelWithString:
            NSLocalizedString("console.about.copyright", comment: ""))
        copyright.font = .systemFont(ofSize: 10.5)
        copyright.textColor = .tertiaryLabelColor

        let stack = NSStackView(views: [icon, title, version, subtitle, links, copyright])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.setCustomSpacing(12, after: icon)
        stack.setCustomSpacing(10, after: version)
        stack.setCustomSpacing(16, after: subtitle)
        stack.setCustomSpacing(20, after: links)
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: centerXAnchor),
            card.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -8),
            card.widthAnchor.constraint(equalToConstant: 420),

            stack.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: card.contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor),
            subtitle.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private func makeLinkButton(_ title: String,
                                symbol: String,
                                tint: NSColor,
                                action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .systemFont(ofSize: 11)
        button.image = NSImage(systemSymbolName: symbol,
                               accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(paletteColors: [tint]))
        button.imagePosition = .imageLeading
        return button
    }

    // MARK: - 动作

    @objc private func openAfdian() {
        open("https://ifdian.net/a/nico2026")
    }

    @objc private func openWebsite() {
        open("https://pinshell.looplooptech.com/")
    }

    @objc private func openRepository() {
        open("https://github.com/\(UpdateChecker.repo)")
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
