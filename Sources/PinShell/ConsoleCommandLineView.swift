import AppKit
import PinShellCore

/// 控制台「CLI」页：安装 `PinShell` 命令、命令速查，以及可下载的 Agent Skill。
final class ConsoleCommandLineView: NSView, ConsoleServicePage {
    private enum LinkState: Equatable {
        case missing
        case linked
        case stale(target: String)
        case occupied
    }

    private struct CommandItem {
        let command: String
        let descriptionKey: String
    }

    private enum InstallMenuItem: Int, CaseIterable {
        case install, reveal, remove

        var titleKey: String {
            switch self {
            case .install: return "console.cli.install.install"
            case .reveal: return "library.menu.reveal"
            case .remove: return "console.cli.install.remove"
            }
        }
    }

    private static let pathLine = "export PATH=\"$HOME/.local/bin:$PATH\""

    private static let commands: [CommandItem] = CLICommandCatalog.commands.compactMap { spec in
        guard let example = spec.consoleExample,
              let descriptionKey = spec.consoleDescriptionKey else { return nil }
        return CommandItem(command: example, descriptionKey: descriptionKey)
    }

    private static var linkURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent(PinShellAppInfo.name, isDirectory: false)
    }

    private let installChip = StatusChip()
    private let installPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let skillDownloadButton = NSButton(
        title: NSLocalizedString("console.cli.skill.download", comment: ""),
        target: nil,
        action: nil)
    private let skillCopyButton = NSButton(
        title: NSLocalizedString("console.cli.skill.copy", comment: ""),
        target: nil,
        action: nil)
    private var skillCopyReset = DelayedReset()
    private var downloadReset = DelayedReset()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - 装配

    private func build() {
        let page = ConsoleScrollPage(horizontalInset: ConsoleTheme.Space.pageInset,
                                     spacing: ConsoleTheme.Space.md)
        page.pinEdges(to: self)
        let stack = page.stack

        let hero = buildHero()
        let tools = buildToolsGroup()
        let skill = buildSkillGroup()
        let commands = buildCommandsGroup()

        for view in [hero, tools, skill, commands] {
            stack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    private func buildHero() -> NSView {
        SettingsPageHeaderView.ready(titleKey: "console.cli.title",
                                     subtitleKey: "console.cli.navSubtitle",
                                     readyKey: "console.cli.ready")
    }

    private func buildToolsGroup() -> SettingsDisclosureGroupView {
        let group = SettingsDisclosureGroupView(
            title: NSLocalizedString("console.cli.tools.title", comment: ""),
            initiallyExpanded: true)

        group.addRow(buildExecutableRow())

        installPopup.controlSize = .small
        installPopup.bezelStyle = .rounded
        for item in InstallMenuItem.allCases {
            installPopup.addItem(withTitle: NSLocalizedString(item.titleKey, comment: ""))
        }
        // 菜单项由刷新逻辑显式启停，避免 AppKit 自动校验把“移除”重新启用。
        installPopup.menu?.autoenablesItems = false
        installPopup.target = self
        installPopup.action = #selector(installAction(_:))
        installPopup.translatesAutoresizingMaskIntoConstraints = false
        installPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 96).isActive = true

        let installTrailing = NSStackView(views: [installChip, installPopup])
        installTrailing.orientation = .horizontal
        installTrailing.spacing = 8
        installTrailing.alignment = .centerY
        installTrailing.setContentHuggingPriority(.required, for: .horizontal)

        let installRow = SettingsRowView(
            title: NSLocalizedString("console.cli.install.title", comment: ""),
            subtitle: NSLocalizedString("console.cli.install.subtitle", comment: ""),
            accessory: installTrailing)
        group.addRow(installRow)
        group.addContent(buildPathHint())

        refreshInstallState()
        return group
    }

    private func buildExecutableRow() -> NSView {
        let title = NSTextField(labelWithString:
            NSLocalizedString("console.cli.executable", comment: ""))
        title.font = ConsoleTheme.Font.rowTitle
        title.textColor = .labelColor
        title.setContentHuggingPriority(.required, for: .horizontal)

        let copy = CopyIconButton(
            text: PinShellAppInfo.executableURL.path,
            accessibilityLabel: NSLocalizedString("console.mcp.copy", comment: ""))

        let titleRow = NSStackView(views: [title, NSView(), copy])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 8

        let path = NSTextField(labelWithString: PinShellAppInfo.executableURL.path)
        path.font = ConsoleTheme.Font.monoMeta
        path.textColor = .secondaryLabelColor
        path.lineBreakMode = .byTruncatingMiddle
        path.maximumNumberOfLines = 1
        path.isSelectable = true
        path.toolTip = PinShellAppInfo.executableURL.path
        path.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let subtitle = NSTextField(labelWithString:
            NSLocalizedString("console.cli.executable.subtitle", comment: ""))
        subtitle.font = ConsoleTheme.Font.caption
        subtitle.textColor = .tertiaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.maximumNumberOfLines = 1
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [titleRow, path, subtitle])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor,
                                           constant: ConsoleTheme.Space.rowInset),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor,
                                            constant: -ConsoleTheme.Space.rowInset),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: ConsoleTheme.Space.rowHeight),
            titleRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            path.widthAnchor.constraint(equalTo: stack.widthAnchor),
            subtitle.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        return container
    }

    private func buildPathHint() -> NSView {
        let hint = NSTextField(wrappingLabelWithString:
            NSLocalizedString("console.cli.path.hint", comment: ""))
        hint.font = ConsoleTheme.Font.caption
        hint.textColor = .secondaryLabelColor
        hint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let codeLabel = NSTextField(labelWithString: Self.pathLine)
        codeLabel.font = ConsoleTheme.Font.monoCode
        codeLabel.textColor = .labelColor
        codeLabel.lineBreakMode = .byTruncatingMiddle
        codeLabel.isSelectable = true
        codeLabel.toolTip = Self.pathLine
        codeLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let copy = CopyIconButton(
            text: Self.pathLine,
            accessibilityLabel: NSLocalizedString("console.cli.path.copy", comment: ""))

        let box = ConsoleInsetView(inset: NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12))
        let codeRow = NSStackView(views: [codeLabel, NSView(), copy])
        codeRow.orientation = .horizontal
        codeRow.alignment = .centerY
        codeRow.spacing = 8
        codeRow.translatesAutoresizingMaskIntoConstraints = false
        box.contentView.addSubview(codeRow)
        NSLayoutConstraint.activate([
            codeRow.leadingAnchor.constraint(equalTo: box.contentView.leadingAnchor),
            codeRow.trailingAnchor.constraint(equalTo: box.contentView.trailingAnchor),
            codeRow.topAnchor.constraint(equalTo: box.contentView.topAnchor),
            codeRow.bottomAnchor.constraint(equalTo: box.contentView.bottomAnchor),
        ])

        let stack = NSStackView(views: [hint, box])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        hint.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        box.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private func buildCommandsGroup() -> SettingsDisclosureGroupView {
        let group = SettingsDisclosureGroupView(
            title: NSLocalizedString("console.cli.commands", comment: ""),
            count: Self.commands.count,
            initiallyExpanded: true)

        for item in Self.commands {
            group.addRow(commandRow(item))
        }

        let hint = NSTextField(wrappingLabelWithString:
            NSLocalizedString("console.cli.commands.hint", comment: ""))
        hint.font = ConsoleTheme.Font.caption
        hint.textColor = .tertiaryLabelColor
        group.addContent(hint, insets: NSEdgeInsets(top: 8, left: ConsoleTheme.Space.rowInset,
                                                   bottom: 12, right: ConsoleTheme.Space.rowInset))
        return group
    }

    private func commandRow(_ item: CommandItem) -> NSView {
        let commandLabel = NSTextField(labelWithString: item.command)
        commandLabel.font = ConsoleTheme.Font.monoCode
        commandLabel.textColor = .labelColor
        commandLabel.lineBreakMode = .byTruncatingMiddle
        commandLabel.maximumNumberOfLines = 1
        commandLabel.isSelectable = true
        commandLabel.toolTip = item.command
        commandLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let descriptionLabel = NSTextField(labelWithString:
            NSLocalizedString(item.descriptionKey, comment: ""))
        descriptionLabel.font = ConsoleTheme.Font.caption
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.lineBreakMode = .byTruncatingTail
        descriptionLabel.maximumNumberOfLines = 1
        descriptionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let text = NSStackView(views: [commandLabel, descriptionLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let copy = CopyIconButton(
            text: item.command,
            accessibilityLabel: NSLocalizedString("console.cli.command.copy", comment: ""))

        let row = NSStackView(views: [text, NSView(), copy])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 8, left: ConsoleTheme.Space.rowInset,
                                      bottom: 8, right: ConsoleTheme.Space.rowInset)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: ConsoleTheme.Space.rowHeight).isActive = true
        return row
    }

    private func buildSkillGroup() -> SettingsDisclosureGroupView {
        let group = SettingsDisclosureGroupView(
            title: NSLocalizedString("console.cli.skill.title", comment: ""),
            initiallyExpanded: true)

        let subtitle = NSTextField(wrappingLabelWithString:
            NSLocalizedString("console.cli.skill.subtitle", comment: ""))
        subtitle.font = ConsoleTheme.Font.caption
        subtitle.textColor = .secondaryLabelColor
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let pathLabel = NSTextField(labelWithString:
            NSLocalizedString("console.cli.skill.path", comment: ""))
        pathLabel.font = ConsoleTheme.Font.monoMeta
        pathLabel.textColor = .tertiaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.isSelectable = true
        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        for (button, symbol, action) in [
            (skillDownloadButton, "arrow.down.circle", #selector(downloadSkill)),
            (skillCopyButton, "doc.on.doc", #selector(copySkill)),
        ] {
            button.bezelStyle = .rounded
            button.controlSize = .regular
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            button.imagePosition = .imageLeading
            button.target = self
            button.action = action
        }

        let buttons = NSStackView(views: [skillDownloadButton, skillCopyButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.alignment = .centerY

        let content = NSStackView(views: [subtitle, pathLabel, buttons])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 8
        subtitle.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        group.addContent(content)
        return group
    }

    // MARK: - 刷新

    func activate() {
        refreshInstallState()
    }

    private func refreshInstallState() {
        let state = currentLinkState()
        let installItem = installPopup.item(at: InstallMenuItem.install.rawValue)
        let removeItem = installPopup.item(at: InstallMenuItem.remove.rawValue)
        installPopup.item(at: InstallMenuItem.reveal.rawValue)?.isEnabled = true

        switch state {
        case .missing:
            installChip.configure(
                text: NSLocalizedString("console.cli.install.notInstalled", comment: ""),
                symbol: "slash.circle",
                style: .neutral,
                toolTip: Self.linkURL.path)
            installItem?.title = NSLocalizedString("console.cli.install.install", comment: "")
            installItem?.isEnabled = true
            removeItem?.isEnabled = false

        case .linked:
            installChip.configure(
                text: NSLocalizedString("console.cli.install.installed", comment: ""),
                symbol: "checkmark.circle.fill",
                style: .positive,
                toolTip: Self.linkURL.path)
            installItem?.title = NSLocalizedString("console.cli.install.installed", comment: "")
            installItem?.isEnabled = false
            removeItem?.isEnabled = true

        case .stale(let target):
            installChip.configure(
                text: NSLocalizedString("console.cli.install.stale", comment: ""),
                symbol: "exclamationmark.triangle.fill",
                style: .warning,
                toolTip: String(format: NSLocalizedString("console.cli.install.staleHint",
                                                          comment: ""), target))
            installItem?.title = NSLocalizedString("console.cli.install.reinstall", comment: "")
            installItem?.isEnabled = true
            removeItem?.isEnabled = true

        case .occupied:
            installChip.configure(
                text: NSLocalizedString("console.cli.install.occupied", comment: ""),
                symbol: "exclamationmark.triangle.fill",
                style: .warning,
                toolTip: NSLocalizedString("console.cli.install.occupiedHint", comment: ""))
            installItem?.title = NSLocalizedString("console.cli.install.install", comment: "")
            installItem?.isEnabled = false
            removeItem?.isEnabled = false
        }
    }

    private static func itemExists(at url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    /// 符号链接指向的目标；不存在、不是符号链接或目标不可读时为 nil。
    private static func symlinkTarget(at url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeSymbolicLink else { return nil }
        return try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)
    }

    private func currentLinkState() -> LinkState {
        let link = Self.linkURL
        guard Self.itemExists(at: link) else { return .missing }
        guard let rawTarget = Self.symlinkTarget(at: link) else { return .occupied }

        let targetURL: URL
        if rawTarget.hasPrefix("/") {
            targetURL = URL(fileURLWithPath: rawTarget)
        } else {
            targetURL = link.deletingLastPathComponent().appendingPathComponent(rawTarget)
        }
        let target = targetURL.standardizedFileURL.resolvingSymlinksInPath().path
        let executable = PinShellAppInfo.executableURL
            .standardizedFileURL.resolvingSymlinksInPath().path
        return target == executable ? .linked : .stale(target: target)
    }

    // MARK: - 安装 / 移除

    @objc private func installAction(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        sender.selectItem(at: InstallMenuItem.install.rawValue)
        guard let item = InstallMenuItem(rawValue: index) else { return }
        switch item {
        case .install: installLink()
        case .reveal: revealLink()
        case .remove: removeLink()
        }
    }

    private func installLink() {
        let manager = FileManager.default
        let link = Self.linkURL
        do {
            try manager.createDirectory(at: link.deletingLastPathComponent(),
                                        withIntermediateDirectories: true,
                                        attributes: nil)
            if Self.itemExists(at: link) {
                guard Self.symlinkTarget(at: link) != nil else {
                    throw CLIInstallError.occupied(link)
                }
                try manager.removeItem(at: link)
            }
            try manager.createSymbolicLink(at: link,
                                           withDestinationURL: PinShellAppInfo.executableURL)
        } catch {
            presentInstallError(error.localizedDescription)
        }
        refreshInstallState()
    }

    private func removeLink() {
        let manager = FileManager.default
        let link = Self.linkURL
        guard Self.symlinkTarget(at: link) != nil else {
            NSSound.beep()
            return
        }
        do {
            try manager.removeItem(at: link)
        } catch {
            presentInstallError(error.localizedDescription)
        }
        refreshInstallState()
    }

    private func revealLink() {
        NSWorkspace.shared.revealInFinder(Self.linkURL)
    }

    private func presentInstallError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("console.cli.install.errorTitle", comment: "")
        alert.informativeText = message
        alert.addButton(withTitle: NSLocalizedString("console.error.ok", comment: ""))
        alert.runAppModal()
    }

    // MARK: - Agent Skill

    private func skillMarkdown() -> String? {
        guard let url = Bundle.main.url(forResource: "SKILL",
                                        withExtension: "md",
                                        subdirectory: "skills/pinshell"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return text
    }

    @objc private func downloadSkill() {
        guard let content = skillMarkdown() else {
            presentSkillError(NSLocalizedString("console.cli.skill.unavailable", comment: ""))
            return
        }

        let panel = NSSavePanel()
        panel.title = NSLocalizedString("console.cli.skill.saveTitle", comment: "")
        panel.message = NSLocalizedString("console.cli.skill.saveMessage", comment: "")
        panel.nameFieldStringValue = "SKILL.md"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory,
                                                      in: .userDomainMask).first

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try Data(content.utf8).write(to: url, options: .atomic)
                self?.flashDownloaded()
            } catch {
                self?.presentSkillError(error.localizedDescription)
            }
        }

        if let window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }

    @objc private func copySkill() {
        guard let content = skillMarkdown() else {
            presentSkillError(NSLocalizedString("console.cli.skill.unavailable", comment: ""))
            return
        }
        guard copyStringToPasteboard(content) else { return }

        skillCopyButton.title = NSLocalizedString("console.events.copied", comment: "")
        skillCopyReset.schedule(after: 1.2) { [weak self] in
            self?.skillCopyButton.title = NSLocalizedString("console.cli.skill.copy", comment: "")
        }
    }

    private func flashDownloaded() {
        skillDownloadButton.title = NSLocalizedString("console.cli.skill.saved", comment: "")
        downloadReset.schedule(after: 1.5) { [weak self] in
            self?.skillDownloadButton.title =
                NSLocalizedString("console.cli.skill.download", comment: "")
        }
    }

    private func presentSkillError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("console.cli.skill.errorTitle", comment: "")
        alert.informativeText = message
        alert.addButton(withTitle: NSLocalizedString("console.error.ok", comment: ""))
        alert.runAppModal()
    }
}

// MARK: - 复制按钮

/// 小号复制按钮：复制文本并把图标短暂换成对勾。
private final class CopyIconButton: NSButton {
    private let copiedText: String
    private var reset = DelayedReset()

    private static let iconConfiguration = NSImage.SymbolConfiguration(pointSize: 12,
                                                                       weight: .regular)

    init(text: String, accessibilityLabel: String) {
        copiedText = text
        super.init(frame: .zero)
        configureIconButton(self, symbol: "doc.on.doc",
                            accessibilityLabel: accessibilityLabel, pointSize: 12)
        imagePosition = .imageOnly
        contentTintColor = .secondaryLabelColor
        target = self
        action = #selector(copyTapped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private static func icon(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(iconConfiguration)
    }

    @objc private func copyTapped() {
        guard copyStringToPasteboard(copiedText) else { return }
        image = Self.icon("checkmark")
        contentTintColor = ConsoleTheme.Color.positive
        reset.schedule(after: 1.2) { [weak self] in
            self?.image = Self.icon("doc.on.doc")
            self?.contentTintColor = .secondaryLabelColor
        }
    }
}

// MARK: - 安装错误

private enum CLIInstallError: LocalizedError {
    case occupied(URL)

    var errorDescription: String? {
        switch self {
        case .occupied(let url):
            return String(format: NSLocalizedString("console.cli.install.errorExists",
                                                     comment: ""), url.path)
        }
    }
}
