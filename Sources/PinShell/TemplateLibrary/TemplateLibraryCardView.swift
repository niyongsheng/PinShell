import AppKit
import PinShellCore

@MainActor
final class TemplateLibraryCardView: NSView {
    private let service: TemplateLibraryService
    private let row: TemplateLibraryService.Row

    var onOpenInstalled: (() -> Void)?

    private let primaryButton = NSButton(title: "", target: nil, action: nil)
    private lazy var menuButton = makeIconButton(
        symbol: "ellipsis.circle",
        accessibilityLabel: NSLocalizedString("library.menu.more", comment: ""),
        target: self,
        action: #selector(menuTapped))

    init(service: TemplateLibraryService, row: TemplateLibraryService.Row) {
        self.service = service
        self.row = row
        super.init(frame: .zero)
        build()
        configure()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func build() {
        let categoryStyle = ConsoleTheme.categoryStyle(for: row.entry.category)
        let iconTile = SettingsIconTile(
            symbol: categoryStyle.symbol,
            tint: categoryStyle.tint,
            size: 30)

        let titleLabel = NSTextField(labelWithString: row.localizedName)
        titleLabel.font = ConsoleTheme.Font.rowTitle
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let descriptionLabel = NSTextField(wrappingLabelWithString: row.localizedDescription)
        descriptionLabel.font = ConsoleTheme.Font.caption
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.maximumNumberOfLines = 2
        descriptionLabel.lineBreakMode = .byWordWrapping
        descriptionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let metaRow = buildMetaRow()

        let textStack = NSStackView(views: [titleLabel, descriptionLabel, metaRow])
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        descriptionLabel.widthAnchor.constraint(lessThanOrEqualTo: textStack.widthAnchor).isActive = true

        primaryButton.bezelStyle = .rounded
        primaryButton.controlSize = .small
        primaryButton.target = self
        primaryButton.action = #selector(primaryTapped)
        primaryButton.setContentHuggingPriority(.required, for: .horizontal)
        primaryButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        let buttonRow = NSStackView(views: [primaryButton, menuButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 6
        buttonRow.alignment = .centerY
        buttonRow.setContentHuggingPriority(.required, for: .horizontal)

        // 弹性占位把右侧操作推到行右缘
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [iconTile, textStack, spacer, buttonRow])
        stack.orientation = .horizontal
        stack.spacing = 12
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 10, left: ConsoleTheme.Space.rowInset,
                                        bottom: 10, right: ConsoleTheme.Space.rowInset)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 64),
            textStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
        ])
    }

    private func configure() {
        let evaluation = row.evaluation
        let readOnly = row.sourceIsReadOnly || service.stateReadOnly

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
        toolTip = [row.localizedName, category, "v\(row.entry.version)",
                   row.isOfficialSource ? "" : row.sourceDisplayName]
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
        let version = makeMetaLabel("v\(row.entry.version)", mono: true)
        let categoryName = service.categoryName(for: row.entry.category)
        let category = makeMetaLabel(categoryName, mono: false)
        category.isHidden = categoryName.isEmpty

        let categoryDot = makeMetaSeparator()
        categoryDot.isHidden = categoryName.isEmpty

        let sizeText = row.entry.preview.map { "\($0.width ?? 0)×\($0.height ?? 0)" } ?? ""
        let size = makeMetaLabel(sizeText, mono: true)
        let sizeDot = makeMetaSeparator()
        size.isHidden = sizeText.isEmpty
        sizeDot.isHidden = sizeText.isEmpty

        // 附加来源的模板标注来源，避免和官方库同名模板混淆。
        let sourceName = row.isOfficialSource ? "" : row.sourceDisplayName
        let source = makeMetaLabel(sourceName, mono: false)
        let sourceDot = makeMetaSeparator()
        source.isHidden = sourceName.isEmpty
        sourceDot.isHidden = sourceName.isEmpty
        source.toolTip = row.source.url.absoluteString

        let row = NSStackView(views: [version, categoryDot, category, sizeDot, size,
                                     sourceDot, source])
        row.orientation = .horizontal
        row.spacing = 5
        row.alignment = .centerY
        return row
    }

    private func makeMetaLabel(_ text: String, mono: Bool) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = mono ? ConsoleTheme.Font.monoMeta : ConsoleTheme.Font.caption
        label.textColor = .tertiaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    private func makeMetaSeparator() -> NSTextField {
        let label = NSTextField(labelWithString: "·")
        label.font = ConsoleTheme.Font.caption
        label.textColor = .tertiaryLabelColor
        return label
    }

    private enum InstallTone {
        case action
        case success
        case warning
    }

    private func setButtonTitle(_ title: String, tone: InstallTone) {
        primaryButton.title = title
        primaryButton.setAccessibilityLabel(title)
        switch tone {
        case .action:
            primaryButton.bezelColor = ConsoleTheme.Color.accent
        case .success:
            primaryButton.bezelColor = nil
        case .warning:
            primaryButton.bezelColor = ConsoleTheme.Color.warning
        }
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
        presentConsoleErrorAlert(error, in: window)
    }
}
