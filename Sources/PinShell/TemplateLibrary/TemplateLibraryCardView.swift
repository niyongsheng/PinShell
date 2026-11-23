import AppKit
import PinShellCore

@MainActor
final class TemplateLibraryCardView: NSView {
    private let service: TemplateLibraryService
    private let row: TemplateLibraryService.Row

    var onOpenInstalled: (() -> Void)?

    private let primaryButton = LibraryInstallButton()
    private let menuButton = NSButton(title: "", target: nil, action: nil)

    init(service: TemplateLibraryService, row: TemplateLibraryService.Row) {
        self.service = service
        self.row = row
        super.init(frame: .zero)
        build()
        configure()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func build() {
        let card = ConsoleCard(
            cornerRadius: 14,
            inset: NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16))
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        let iconTile = ConsoleIconTile(
            symbol: ConsoleTheme.categorySymbol(for: row.entry.category),
            size: 38,
            symbolPointSize: 17,
            style: .neutral)

        let titleLabel = NSTextField(labelWithString: row.localizedName)
        titleLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1

        let descriptionLabel = NSTextField(wrappingLabelWithString: row.localizedDescription)
        descriptionLabel.font = .systemFont(ofSize: 11.5)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.maximumNumberOfLines = 2
        descriptionLabel.lineBreakMode = .byWordWrapping

        let metaRow = buildMetaRow()

        let textStack = NSStackView(views: [titleLabel, descriptionLabel, metaRow])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        descriptionLabel.widthAnchor.constraint(lessThanOrEqualTo: textStack.widthAnchor).isActive = true

        primaryButton.target = self
        primaryButton.action = #selector(primaryTapped)

        menuButton.image = NSImage(systemSymbolName: "ellipsis.circle",
                                   accessibilityDescription: nil)
        menuButton.bezelStyle = .texturedRounded
        menuButton.isBordered = false
        menuButton.target = self
        menuButton.action = #selector(menuTapped)
        menuButton.toolTip = NSLocalizedString("library.menu.more", comment: "")
        menuButton.setAccessibilityLabel(NSLocalizedString("library.menu.more", comment: ""))

        let buttonRow = NSStackView(views: [primaryButton, menuButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 4
        buttonRow.alignment = .centerY
        buttonRow.setContentHuggingPriority(.required, for: .horizontal)

        // 弹性占位把右侧操作推到卡片右缘
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [iconTile, textStack, spacer, buttonRow])
        stack.orientation = .horizontal
        stack.spacing = 12
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: card.contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor),
            textStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
        ])
    }

    private func configure() {
        let evaluation = row.evaluation
        let readOnly = service.isCatalogReadOnly || service.stateReadOnly

        if evaluation.needsNewerApp {
            setButtonTitle(String(
                format: NSLocalizedString("library.action.requires", comment: ""),
                row.entry.minimumAppVersion),
                tone: .action)
            primaryButton.isEnabled = false
        } else if evaluation.installState == .installed && !evaluation.updateAvailable {
            setButtonTitle(NSLocalizedString("library.action.open", comment: ""),
                           tone: .success)
            primaryButton.isEnabled = true
        } else if evaluation.installState == .unmanagedLocal {
            setButtonTitle(NSLocalizedString("library.action.replace", comment: ""),
                           tone: .warning)
            primaryButton.isEnabled = !service.isInstalling && !readOnly
        } else if evaluation.installState == .notInstalled {
            setButtonTitle(NSLocalizedString("library.action.get", comment: ""),
                           tone: .action)
            primaryButton.isEnabled = !service.isInstalling && !readOnly
        } else {
            setButtonTitle(NSLocalizedString(
                evaluation.isRepair ? "library.action.repair" : "library.action.update",
                comment: ""),
                tone: evaluation.isRepair ? .warning : .action)
            primaryButton.isEnabled = !service.isInstalling && !readOnly
        }

        // 状态提示收进按钮 tooltip，卡片上只保留一个可操作按钮。
        primaryButton.toolTip = statusText(for: evaluation)

        let category = service.categoryName(for: row.entry.category)
        toolTip = [row.localizedName, category, "v\(row.entry.version)"]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private func statusText(for evaluation: TemplateLibraryEvaluation) -> String {
        let key: String
        if evaluation.needsNewerApp {
            key = "library.state.incompatible"
        } else if evaluation.installState == .notInstalled {
            key = "library.state.notInstalled"
        } else if evaluation.installState == .unmanagedLocal {
            key = "library.state.local"
        } else if evaluation.isIgnored {
            key = "library.state.ignored"
        } else if evaluation.isEdited {
            key = "library.state.edited"
        } else if evaluation.updateAvailable {
            key = evaluation.isRepair ? "library.state.repair" : "library.state.update"
        } else {
            key = "library.state.installed"
        }
        return NSLocalizedString(key, comment: "")
    }

    private func buildMetaRow() -> NSView {
        let version = makeMetaLabel("v\(row.entry.version)")
        let categoryName = service.categoryName(for: row.entry.category)
        let categoryTag = LibraryCategoryTag()
        categoryTag.configure(text: categoryName)
        categoryTag.isHidden = categoryName.isEmpty

        let categoryDot = makeMetaSeparator()
        categoryDot.isHidden = categoryName.isEmpty

        let sizeText = row.entry.preview.map { "\($0.width ?? 0)×\($0.height ?? 0)" } ?? ""
        let size = makeMetaLabel(sizeText)
        let sizeDot = makeMetaSeparator()
        size.isHidden = sizeText.isEmpty
        sizeDot.isHidden = sizeText.isEmpty

        let row = NSStackView(views: [version, categoryDot, categoryTag, sizeDot, size])
        row.orientation = .horizontal
        row.spacing = 5
        row.alignment = .centerY
        return row
    }

    private func makeMetaLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = ConsoleTheme.Font.monoMeta
        label.textColor = .tertiaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    private func makeMetaSeparator() -> NSTextField {
        let label = NSTextField(labelWithString: "·")
        label.font = ConsoleTheme.Font.monoMeta
        label.textColor = .tertiaryLabelColor
        return label
    }

    private func setButtonTitle(_ title: String, tone: LibraryInstallButton.Tone) {
        primaryButton.setInstallTitle(title, tone: tone)
    }

    // MARK: - Actions

    @objc private func primaryTapped() {
        let evaluation = row.evaluation
        if evaluation.installState == .installed && !evaluation.updateAvailable {
            onOpenInstalled?()
            return
        }
        guard !evaluation.needsNewerApp else { return }

        let proceed: (TemplateLibraryService.ConflictDecision) -> Void = { [weak self] decision in
            guard let self else { return }
            Task { @MainActor in
                do {
                    try await self.service.install(self.row, conflict: decision)
                } catch {
                    self.showErrorAlert(error)
                }
            }
        }

        if service.conflictDecisionNeeded(for: row) {
            let alert = NSAlert()
            let edited = row.record != nil
            alert.messageText = NSLocalizedString(
                edited ? "library.conflict.editedTitle" : "library.conflict.unmanagedTitle",
                comment: "")
            alert.informativeText = NSLocalizedString(
                edited ? "library.conflict.editedInfo" : "library.conflict.unmanagedInfo",
                comment: "")
            alert.alertStyle = .warning
            alert.addButton(withTitle: NSLocalizedString("library.conflict.backup", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("library.conflict.replace", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("library.conflict.cancel", comment: ""))
            let handler: (NSApplication.ModalResponse) -> Void = { response in
                switch response {
                case .alertFirstButtonReturn:
                    proceed(.backupAndInstall)
                case .alertSecondButtonReturn:
                    proceed(.replace)
                default:
                    proceed(.cancel)
                }
            }
            if let window {
                alert.beginSheetModal(for: window, completionHandler: handler)
            } else {
                handler(alert.runModal())
            }
        } else {
            proceed(.replace)
        }
    }

    @objc private func menuTapped() {
        let menu = NSMenu()
        let detail = NSMenuItem(title: NSLocalizedString("library.menu.details", comment: ""),
                                action: #selector(showDetails), keyEquivalent: "")
        detail.target = self
        menu.addItem(detail)

        let website = NSMenuItem(title: NSLocalizedString("library.menu.website", comment: ""),
                                 action: #selector(openWebsite), keyEquivalent: "")
        website.target = self
        menu.addItem(website)

        if row.evaluation.updateAvailable && !row.evaluation.isIgnored {
            let ignore = NSMenuItem(
                title: String(format: NSLocalizedString("library.menu.ignore", comment: ""),
                              row.entry.version),
                action: #selector(ignoreVersion), keyEquivalent: "")
            ignore.target = self
            menu.addItem(ignore)
        }
        if row.evaluation.isIgnored {
            let unignore = NSMenuItem(title: NSLocalizedString("library.menu.unignore", comment: ""),
                                      action: #selector(unignoreVersion), keyEquivalent: "")
            unignore.target = self
            menu.addItem(unignore)
        }
        if row.evaluation.installState != .notInstalled {
            menu.addItem(.separator())
            let reveal = NSMenuItem(title: NSLocalizedString("library.menu.reveal", comment: ""),
                                    action: #selector(reveal), keyEquivalent: "")
            reveal.target = self
            menu.addItem(reveal)
        }

        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: menuButton.bounds.height + 4),
                   in: menuButton)
    }

    @objc private func showDetails() {
        let entry = row.entry
        var lines: [String] = []
        if let listing = row.localizedListing {
            if let tagline = listing.tagline, !tagline.isEmpty {
                lines.append(tagline)
            }
            if let highlights = listing.highlights, !highlights.isEmpty {
                lines.append(NSLocalizedString("library.detail.highlights", comment: ""))
                lines.append(contentsOf: highlights.map { "• \($0)" })
            }
        }
        if let author = entry.author {
            lines.append("")
            var line = "\(NSLocalizedString("library.detail.author", comment: "")) · \(author.name)"
            if let url = author.url {
                line += "\n\(url)"
            }
            lines.append(line)
        }
        if let notes = entry.changelogNotes(
            version: entry.version,
            preferredLanguages: LanguageTag.templatePreferredLanguages) {
            lines.append("")
            lines.append("\(NSLocalizedString("library.detail.changelog", comment: "")) · v\(entry.version)")
            lines.append(notes)
        }
        if let size = entry.preview {
            lines.append("")
            lines.append("v\(entry.version) · \(size.width ?? 0)×\(size.height ?? 0)")
        }

        let alert = NSAlert()
        alert.messageText = row.localizedName
        alert.informativeText = lines.joined(separator: "\n")
        alert.addButton(withTitle: NSLocalizedString("library.menu.website", comment: ""))
        let authorURL = entry.author?.url.flatMap { URL(string: $0) }
        if authorURL != nil {
            alert.addButton(withTitle: NSLocalizedString("library.detail.authorPage", comment: ""))
        }
        alert.addButton(withTitle: NSLocalizedString("library.detail.close", comment: ""))
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            service.openWebsite(for: row)
        } else if let authorURL, response == .alertSecondButtonReturn {
            NSWorkspace.shared.open(authorURL)
        }
    }

    @objc private func openWebsite() {
        service.openWebsite(for: row)
    }

    @objc private func ignoreVersion() {
        do {
            try service.ignore(row)
        } catch {
            showErrorAlert(error)
        }
    }

    @objc private func unignoreVersion() {
        do {
            try service.unignore(row)
        } catch {
            showErrorAlert(error)
        }
    }

    @objc private func reveal() {
        service.revealInFinder(row)
    }

    private func showErrorAlert(_ error: Error) {
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
}

/// App Store 风格的安装/打开胶囊按钮：浅色底 + 强调色文字，状态直接体现在标题上。
private final class LibraryInstallButton: NSButton {
    enum Tone {
        case action
        case success
        case warning

        var color: NSColor {
            switch self {
            case .action: return ConsoleTheme.Color.accent
            case .success: return ConsoleTheme.Color.positive
            case .warning: return ConsoleTheme.Color.warning
            }
        }
    }

    private static let fill = ConsoleTheme.Color.insetFill
    private static let height: CGFloat = 26

    private var tone: Tone = .action

    init() {
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        font = .systemFont(ofSize: 12, weight: .medium)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = Self.height / 2
        layer?.masksToBounds = true
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        heightAnchor.constraint(equalToConstant: Self.height).isActive = true
        updateFill()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize {
        let titleSize = attributedTitle.size()
        return NSSize(width: max(ceil(titleSize.width) + 22, 52), height: Self.height)
    }

    override var isEnabled: Bool {
        didSet { updateTitleColor() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        performWithEffectiveAppearance { [weak self] in
            self?.updateFill()
        }
    }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        updateFill(pressed: flag)
    }

    func setInstallTitle(_ title: String, tone: Tone) {
        self.title = title
        self.tone = tone
        setAccessibilityLabel(title)
        updateTitleColor()
        invalidateIntrinsicContentSize()
    }

    private func updateTitleColor() {
        let color: NSColor = isEnabled ? tone.color : .tertiaryLabelColor
        contentTintColor = color
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: font ?? .systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: color,
        ])
    }

    private func updateFill(pressed: Bool = false) {
        performWithEffectiveAppearance { [weak self] in
            guard let self else { return }
            let color = pressed && isEnabled
                ? tone.color.withAlphaComponent(0.16)
                : Self.fill
            layer?.backgroundColor = color.cgColor
        }
    }
}

/// 分类标签：低对比度胶囊标签，避免抢占模板名称与安装操作的视觉层级。
private final class LibraryCategoryTag: NSView {
    private static let height: CGFloat = 18
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = 4.5
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: Self.height),
        ])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        updateFill()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: ceil(label.intrinsicContentSize.width) + 12, height: Self.height)
    }

    func configure(text: String) {
        label.stringValue = text
        invalidateIntrinsicContentSize()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        performWithEffectiveAppearance { [weak self] in
            self?.updateFill()
        }
    }

    private func updateFill() {
        layer?.backgroundColor = ConsoleTheme.Color.insetFill.cgColor
    }
}
