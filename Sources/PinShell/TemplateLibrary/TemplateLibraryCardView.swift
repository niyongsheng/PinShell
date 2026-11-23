import AppKit
import PinShellCore

@MainActor
final class TemplateLibraryCardView: NSView {
    private let service: TemplateLibraryService
    private let row: TemplateLibraryService.Row

    var onOpenInstalled: (() -> Void)?

    private let preview = LibraryPreviewView()
    private let statusChip = StatusChip()
    private let primaryButton = NSButton(title: "", target: nil, action: nil)
    private let menuButton = NSButton(title: "", target: nil, action: nil)

    private static let actionBlue = NSColor(srgbRed: 0.16, green: 0.43,
                                            blue: 0.85, alpha: 1)

    init(service: TemplateLibraryService, row: TemplateLibraryService.Row) {
        self.service = service
        self.row = row
        super.init(frame: .zero)
        build()
        configure()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func build() {
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.38).cgColor

        preview.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            preview.widthAnchor.constraint(equalToConstant: 92),
            preview.heightAnchor.constraint(equalToConstant: 68),
        ])

        let titleLabel = NSTextField(labelWithString: row.localizedName)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1

        let descriptionLabel = NSTextField(wrappingLabelWithString: row.localizedDescription)
        descriptionLabel.font = .systemFont(ofSize: 11)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.maximumNumberOfLines = 2
        descriptionLabel.lineBreakMode = .byWordWrapping

        let metaLabel = NSTextField(labelWithString: metaText())
        metaLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        metaLabel.textColor = .tertiaryLabelColor
        metaLabel.lineBreakMode = .byTruncatingTail

        let textStack = NSStackView(views: [titleLabel, descriptionLabel, metaLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        descriptionLabel.widthAnchor.constraint(lessThanOrEqualTo: textStack.widthAnchor).isActive = true

        primaryButton.target = self
        primaryButton.action = #selector(primaryTapped)
        primaryButton.bezelStyle = .rounded
        primaryButton.controlSize = .regular
        primaryButton.font = .systemFont(ofSize: 12, weight: .medium)

        menuButton.image = NSImage(systemSymbolName: "ellipsis.circle",
                                   accessibilityDescription: "More")
        menuButton.bezelStyle = .texturedRounded
        menuButton.isBordered = false
        menuButton.target = self
        menuButton.action = #selector(menuTapped)
        menuButton.toolTip = NSLocalizedString("library.menu.more", comment: "")

        let buttonRow = NSStackView(views: [primaryButton, menuButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 2
        buttonRow.alignment = .centerY

        let rightStack = NSStackView(views: [statusChip, buttonRow])
        rightStack.orientation = .vertical
        rightStack.alignment = .trailing
        rightStack.spacing = 8
        rightStack.setContentHuggingPriority(.required, for: .horizontal)

        let stack = NSStackView(views: [preview, textStack, rightStack])
        stack.orientation = .horizontal
        stack.spacing = 14
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            textStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
        ])
    }

    private func configure() {
        let category = service.categoryName(for: row.entry.category)
        preview.configure(category: row.entry.category,
                          name: row.localizedName,
                          size: row.entry.preview)

        let evaluation = row.evaluation
        if evaluation.needsNewerApp {
            statusChip.update(text: NSLocalizedString("library.state.incompatible", comment: ""),
                              active: true, activeColor: .systemOrange, symbol: "exclamationmark.triangle.fill")
        } else if evaluation.installState == .notInstalled {
            statusChip.update(text: NSLocalizedString("library.state.notInstalled", comment: ""),
                              active: false, symbol: "circle")
        } else if evaluation.installState == .unmanagedLocal {
            statusChip.update(text: NSLocalizedString("library.state.local", comment: ""),
                              active: false, symbol: "doc")
        } else if evaluation.isIgnored {
            statusChip.update(text: NSLocalizedString("library.state.ignored", comment: ""),
                              active: false, symbol: "bell.slash")
        } else if evaluation.isEdited {
            statusChip.update(text: NSLocalizedString("library.state.edited", comment: ""),
                              active: true, activeColor: .systemOrange, symbol: "pencil")
        } else if evaluation.updateAvailable {
            statusChip.update(
                text: NSLocalizedString(
                    evaluation.isRepair ? "library.state.repair" : "library.state.update",
                    comment: ""),
                active: true, activeColor: Self.actionBlue,
                symbol: evaluation.isRepair ? "wrench.and.screwdriver" : "arrow.down.circle.fill")
        } else {
            statusChip.update(text: NSLocalizedString("library.state.installed", comment: ""),
                              active: true, activeColor: .systemGreen, symbol: "checkmark.circle.fill")
        }

        if evaluation.needsNewerApp {
            primaryButton.title = String(
                format: NSLocalizedString("library.action.requires", comment: ""),
                row.entry.minimumAppVersion)
            primaryButton.isEnabled = false
            primaryButton.bezelColor = nil
        } else if evaluation.installState == .installed && !evaluation.updateAvailable {
            primaryButton.title = NSLocalizedString("library.action.open", comment: "")
            primaryButton.isEnabled = true
            primaryButton.bezelColor = nil
        } else if evaluation.installState == .unmanagedLocal {
            primaryButton.title = NSLocalizedString("library.action.replace", comment: "")
            primaryButton.isEnabled = !service.isInstalling
            stylePrimary()
        } else if evaluation.installState == .notInstalled {
            primaryButton.title = NSLocalizedString("library.action.get", comment: "")
            primaryButton.isEnabled = !service.isInstalling
            stylePrimary()
        } else {
            primaryButton.title = NSLocalizedString(
                evaluation.isRepair ? "library.action.repair" : "library.action.update",
                comment: "")
            primaryButton.isEnabled = !service.isInstalling
            stylePrimary()
        }

        let readOnly = service.isCatalogReadOnly || service.stateReadOnly
        if readOnly,
           evaluation.installState != .installed || evaluation.updateAvailable {
            primaryButton.isEnabled = false
        }

        toolTip = "\(row.localizedName) · \(category) · v\(row.entry.version)"
    }

    private func metaText() -> String {
        let category = service.categoryName(for: row.entry.category)
        let size = row.entry.preview.map { "\($0.width ?? 0)×\($0.height ?? 0)" } ?? ""
        return ["v\(row.entry.version)", category, size]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private func stylePrimary() {
        primaryButton.bezelColor = Self.actionBlue
        primaryButton.contentTintColor = .white
        primaryButton.attributedTitle = NSAttributedString(
            string: primaryButton.title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.white,
            ]
        )
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
        alert.addButton(withTitle: NSLocalizedString("library.detail.close", comment: ""))
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            service.openWebsite(for: row)
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

/// 原生绘制的模板海报：窗口轮廓 + 分类符号 + 尺寸，不在安装前执行远端 HTML。
private final class LibraryPreviewView: NSView {
    private let bar = NSView()
    private let symbolView = NSImageView()
    private let sizeLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func build() {
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.55).cgColor

        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.quaternaryLabelColor
            .withAlphaComponent(0.35).cgColor
        bar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar)

        for index in 0..<3 {
            let dot = NSView()
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 1.5
            dot.layer?.backgroundColor = NSColor.tertiaryLabelColor
                .withAlphaComponent(0.6).cgColor
            dot.translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview(dot)
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: 3),
                dot.heightAnchor.constraint(equalToConstant: 3),
                dot.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
                dot.leadingAnchor.constraint(equalTo: bar.leadingAnchor,
                                             constant: 6 + CGFloat(index) * 6),
            ])
        }

        symbolView.imageScaling = .scaleProportionallyDown
        symbolView.contentTintColor = .secondaryLabelColor
        symbolView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(symbolView)

        sizeLabel.font = .monospacedDigitSystemFont(ofSize: 8, weight: .regular)
        sizeLabel.textColor = .tertiaryLabelColor
        sizeLabel.alignment = .right
        sizeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sizeLabel)

        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bar.topAnchor.constraint(equalTo: topAnchor),
            bar.heightAnchor.constraint(equalToConstant: 13),

            symbolView.centerXAnchor.constraint(equalTo: centerXAnchor),
            symbolView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 3),
            symbolView.widthAnchor.constraint(equalToConstant: 26),
            symbolView.heightAnchor.constraint(equalToConstant: 26),

            sizeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            sizeLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])
    }

    func configure(category: String?, name: String,
                   size: TemplateLibraryPreview?) {
        let symbol: String
        switch category {
        case "productivity": symbol = "checklist"
        case "focus": symbol = "timer"
        case "monitoring": symbol = "gauge.with.dots.needle.bottom.50percent"
        case "companion": symbol = "pawprint.fill"
        case "media": symbol = "music.note"
        case "play": symbol = "gamecontroller.fill"
        case "social": symbol = "person.2.fill"
        default: symbol = "rectangle.on.rectangle"
        }
        symbolView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: name)
        if let size {
            sizeLabel.stringValue = "\(size.width ?? 0)×\(size.height ?? 0)"
        } else {
            sizeLabel.stringValue = ""
        }
    }
}
