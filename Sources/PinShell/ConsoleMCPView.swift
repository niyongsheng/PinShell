import AppKit
import PinShellCore

/// 控制台 MCP 页：stdio 服务配置、可用工具、控制通道。
final class ConsoleMCPView: NSView, ConsoleServicePage {
    private let configLabel = NSTextField(wrappingLabelWithString: "")
    private let socketLabel = NSTextField(labelWithString: "")
    private let copyConfigButton = NSButton(title: NSLocalizedString("console.mcp.copyConfig", comment: ""),
                                            target: nil, action: nil)
    private let copySocketButton = NSButton(title: NSLocalizedString("console.mcp.copy", comment: ""),
                                            target: nil, action: nil)
    private var copyResetWork: DispatchWorkItem?
    private var configText = ""
    private var clientRows: [ClientRow] = []

    private struct ClientRow {
        let client: MCPClient
        let view: NSView
        let popup: MCPClientPopupButton
        let chip: StatusChip
        let pathLabel: NSTextField
    }

    /// SF Symbol 仅 UI 使用；工具名与描述来自 MCPToolSet（单一来源）。
    private static let toolSymbols: [String: String] = [
        "pinshell_html": "rectangle.on.rectangle",
        "pinshell_show": "macwindow",
        "pinshell_eval": "chevron.left.forwardslash.chevron.right",
        "pinshell_emit": "paperplane",
        "pinshell_set": "slider.horizontal.3",
        "pinshell_status": "info.circle",
        "pinshell_templates": "list.bullet.rectangle",
        "pinshell_template_read": "doc.text",
        "pinshell_template_write": "square.and.pencil",
        "pinshell_template_delete": "trash",
        "pinshell_template_show": "play.rectangle",
        "pinshell_poll_events": "tray.and.arrow.down",
        "pinshell_await_event": "hourglass",
        "pinshell_state": "curlybraces",
        "pinshell_close": "xmark.circle",
    ]

    private final class MCPClientPopupButton: NSPopUpButton {
        var client: MCPClient = .claudeCode
    }

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
        let clients = buildClientsCard()
        let config = buildConfigCard()
        let tools = buildToolsCard()
        let prompts = buildPromptsCard()
        let channel = buildChannelCard()

        for view in [hero, clients, config, tools, prompts, channel] {
            stack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    private func buildHero() -> NSView {
        let readyChip = StatusChip()
        readyChip.configure(text: NSLocalizedString("console.mcp.ready", comment: ""),
                            symbol: "checkmark.circle.fill",
                            style: .positive)
        return SettingsPageHeaderView(
            title: NSLocalizedString("console.mcp.title", comment: ""),
            subtitle: NSLocalizedString("console.mcp.navSubtitle", comment: ""),
            accessory: readyChip)
    }

    // MARK: - 客户端自动配置

    private func buildClientsCard() -> NSView {
        let refresh = makeSymbolButton(symbol: "arrow.clockwise",
                                       target: self,
                                       action: #selector(refreshClientsTapped),
                                       accessibilityLabel:
                                        NSLocalizedString("console.mcp.clients.refresh", comment: ""))
        refresh.bezelStyle = .rounded
        refresh.controlSize = .small

        let group = SettingsDisclosureGroupView(
            title: NSLocalizedString("console.mcp.clients.title", comment: ""),
            accessories: [refresh],
            initiallyExpanded: true)

        for client in MCPClient.allCases {
            let row = buildClientRow(client)
            clientRows.append(row)
            group.addRow(row.view)
            row.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
        }

        let hint = NSTextField(wrappingLabelWithString:
            NSLocalizedString("console.mcp.clients.hint", comment: ""))
        hint.font = ConsoleTheme.Font.caption
        hint.textColor = .tertiaryLabelColor
        hint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        group.addContent(hint, insets: NSEdgeInsets(top: 8, left: ConsoleTheme.Space.rowInset,
                                                   bottom: 12, right: ConsoleTheme.Space.rowInset))

        return group
    }

    private func buildClientRow(_ client: MCPClient) -> ClientRow {
        let name = NSTextField(labelWithString: client.displayName)
        name.font = ConsoleTheme.Font.rowTitle
        name.textColor = .labelColor
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let pathLabel = NSTextField(labelWithString: "")
        pathLabel.font = ConsoleTheme.Font.monoMeta
        pathLabel.textColor = .tertiaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let text = NSStackView(views: [name, pathLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let popup = MCPClientPopupButton(frame: .zero, pullsDown: false)
        popup.client = client
        popup.controlSize = .small
        popup.bezelStyle = .rounded
        popup.addItem(withTitle: NSLocalizedString("console.mcp.clients.auto", comment: ""))
        popup.addItem(withTitle: NSLocalizedString("console.mcp.clients.reveal", comment: ""))
        popup.addItem(withTitle: NSLocalizedString("console.mcp.clients.remove", comment: ""))
        // 菜单项由刷新逻辑显式启停，避免 AppKit 自动校验把“移除配置”重新启用
        popup.menu?.autoenablesItems = false
        popup.target = self
        popup.action = #selector(clientAction(_:))
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.setContentHuggingPriority(.required, for: .horizontal)
        popup.setContentCompressionResistancePriority(.required, for: .horizontal)
        popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 96).isActive = true

        let chip = StatusChip()

        let trailing = NSStackView(views: [popup, chip])
        trailing.orientation = .horizontal
        trailing.spacing = 8
        trailing.alignment = .centerY
        trailing.setContentHuggingPriority(.required, for: .horizontal)

        let row = NSStackView(views: [text, NSView(), trailing])
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 8, left: ConsoleTheme.Space.rowInset,
                                      bottom: 8, right: ConsoleTheme.Space.rowInset)
        return ClientRow(client: client, view: row, popup: popup,
                         chip: chip, pathLabel: pathLabel)
    }

    private var clientsRefreshGeneration = 0

    /// 客户端状态需要读取并解析可能很大的配置文件，放到后台计算，回主线程更新。
    private func refreshClients() {
        let context = MCPClientContext.current
        let executable = Self.executableURL
        let entries = clientRows.map { ($0, $0.client.configURL(in: context)) }

        clientsRefreshGeneration += 1
        let generation = clientsRefreshGeneration
        for (row, url) in entries {
            row.pathLabel.stringValue = Self.abbreviate(url.path, home: context.home.path)
            row.pathLabel.toolTip = url.path
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let statuses = entries.map { $0.0.client.status(executable: executable, in: context) }
            DispatchQueue.main.async {
                guard let self, generation == self.clientsRefreshGeneration else { return }
                let statusKeys = (
                    detected: NSLocalizedString("console.mcp.clients.notDetected", comment: ""),
                    configured: NSLocalizedString("console.mcp.clients.configured", comment: ""),
                    stale: NSLocalizedString("console.mcp.clients.stale", comment: ""),
                    notConfigured: NSLocalizedString("console.mcp.clients.notConfigured", comment: "")
                )

                for ((row, url), status) in zip(entries, statuses) {
                    row.popup.isEnabled = status.detected
                    row.popup.toolTip = status.detected
                        ? nil
                        : NSLocalizedString("console.mcp.clients.notDetectedHint", comment: "")
                    row.popup.menu?.item(at: 2)?.isEnabled = status.configured

                    if !status.detected {
                        row.chip.configure(text: statusKeys.detected,
                                           symbol: "minus.circle",
                                           style: .neutral)
                    } else if status.needsUpdate {
                        row.chip.configure(
                            text: statusKeys.stale,
                            symbol: "exclamationmark.triangle.fill",
                            style: .warning,
                            toolTip: String(
                                format: NSLocalizedString("console.mcp.clients.staleHint", comment: ""),
                                executable.path))
                    } else if status.configured {
                        row.chip.configure(text: statusKeys.configured,
                                           symbol: "checkmark.circle.fill",
                                           style: .positive,
                                           toolTip: url.path)
                    } else {
                        row.chip.configure(text: statusKeys.notConfigured,
                                           symbol: "slash.circle",
                                           style: .neutral)
                    }
                }
            }
        }
    }

    @objc private func refreshClientsTapped() {
        refreshClients()
    }

    @objc private func clientAction(_ sender: MCPClientPopupButton) {
        let index = sender.indexOfSelectedItem
        sender.selectItem(at: 0)
        guard sender.isEnabled else { return }

        switch index {
        case 0:
            configure(sender.client)
        case 1:
            revealConfig(sender.client)
        case 2:
            removeConfig(sender.client)
        default:
            break
        }
    }

    private func configure(_ client: MCPClient) {
        do {
            try client.install(executable: Self.executableURL)
        } catch {
            presentConfigError(error, client: client)
        }
        refreshClients()
    }

    private func removeConfig(_ client: MCPClient) {
        do {
            try client.uninstall()
        } catch {
            presentConfigError(error, client: client)
        }
        refreshClients()
    }

    private func revealConfig(_ client: MCPClient) {
        let url = client.configURL()
        let manager = FileManager.default
        if manager.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else if manager.fileExists(atPath: url.deletingLastPathComponent().path) {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        } else {
            NSSound.beep()
        }
    }

    private func presentConfigError(_ error: Error, client: MCPClient) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(
            format: NSLocalizedString("console.mcp.clients.errorTitle", comment: ""),
            client.displayName)
        if let configError = error as? MCPClientConfigError {
            switch configError {
            case .invalidJSON(let url):
                alert.informativeText = String(
                    format: NSLocalizedString("console.mcp.clients.errorJSON", comment: ""),
                    url.path)
            case .invalidStructure(let url):
                alert.informativeText = String(
                    format: NSLocalizedString("console.mcp.clients.errorStructure", comment: ""),
                    url.path)
            case .unreadable(let url):
                alert.informativeText = String(
                    format: NSLocalizedString("console.mcp.clients.errorUnreadable", comment: ""),
                    url.path)
            }
        } else {
            alert.informativeText = error.localizedDescription
        }
        alert.addButton(withTitle: NSLocalizedString("console.error.ok", comment: ""))
        alert.runAppModal()
    }

    private static var executableURL: URL {
        Bundle.main.executableURL
            ?? URL(fileURLWithPath: CommandLine.arguments.first ?? "PinShell")
    }

    private static func abbreviate(_ path: String, home: String) -> String {
        guard path.hasPrefix(home + "/") else { return path }
        return "~" + String(path.dropFirst(home.count))
    }

    private func buildConfigCard() -> NSView {
        copyConfigButton.bezelStyle = .rounded
        copyConfigButton.controlSize = .small
        copyConfigButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copyConfigButton.imagePosition = .imageLeading
        copyConfigButton.target = self
        copyConfigButton.action = #selector(copyConfig)

        let group = SettingsDisclosureGroupView(
            title: NSLocalizedString("console.mcp.config", comment: ""),
            accessories: [copyConfigButton])

        let subtitle = NSTextField(wrappingLabelWithString:
            NSLocalizedString("console.mcp.config.subtitle", comment: ""))
        subtitle.font = ConsoleTheme.Font.caption
        subtitle.textColor = .secondaryLabelColor
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        configLabel.isSelectable = true
        configLabel.font = ConsoleTheme.Font.monoCode
        configLabel.textColor = .labelColor
        configLabel.maximumNumberOfLines = 0
        configLabel.lineBreakMode = .byWordWrapping
        configLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let box = ConsoleInsetView(inset: NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12))
        configLabel.translatesAutoresizingMaskIntoConstraints = false
        box.contentView.addSubview(configLabel)
        NSLayoutConstraint.activate([
            configLabel.leadingAnchor.constraint(equalTo: box.contentView.leadingAnchor),
            configLabel.trailingAnchor.constraint(equalTo: box.contentView.trailingAnchor),
            configLabel.topAnchor.constraint(equalTo: box.contentView.topAnchor),
            configLabel.bottomAnchor.constraint(equalTo: box.contentView.bottomAnchor),
        ])

        let content = NSStackView(views: [subtitle, box])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 8
        subtitle.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        box.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        group.addContent(content)

        return group
    }

    private func buildToolsCard() -> NSView {
        let group = SettingsDisclosureGroupView(
            title: NSLocalizedString("console.mcp.tools", comment: ""),
            count: MCPToolSet.all.count)

        for tool in MCPToolSet.all {
            group.addRow(toolRow(
                name: tool.name,
                symbol: Self.toolSymbols[tool.name] ?? "wrench",
                description: tool.description))
        }

        return group
    }

    private func buildPromptsCard() -> NSView {
        let group = SettingsDisclosureGroupView(
            title: NSLocalizedString("console.mcp.prompts", comment: ""),
            count: MCPPromptCatalog.definitions.count)

        for prompt in MCPPromptCatalog.definitions {
            group.addRow(toolRow(name: prompt.name,
                                 symbol: "wand.and.stars",
                                 description: prompt.description))
        }

        return group
    }

    private func toolRow(name: String, symbol: String, description: String) -> NSView {
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol,
                                              accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
        ])

        let nameLabel = NSTextField(labelWithString: name)
        nameLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        nameLabel.textColor = .labelColor
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let descLabel = NSTextField(labelWithString: description)
        descLabel.font = ConsoleTheme.Font.caption
        descLabel.textColor = .secondaryLabelColor
        descLabel.lineBreakMode = .byTruncatingTail
        descLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        descLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let text = NSStackView(views: [nameLabel, descLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [icon, text])
        row.orientation = .horizontal
        row.spacing = 9
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 8, left: ConsoleTheme.Space.rowInset,
                                      bottom: 8, right: ConsoleTheme.Space.rowInset)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: ConsoleTheme.Space.rowHeight).isActive = true
        return row
    }

    private func buildChannelCard() -> NSView {
        copySocketButton.bezelStyle = .rounded
        copySocketButton.controlSize = .small
        copySocketButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copySocketButton.imagePosition = .imageLeading
        copySocketButton.target = self
        copySocketButton.action = #selector(copySocket)

        let group = SettingsDisclosureGroupView(
            title: NSLocalizedString("console.mcp.channel", comment: ""),
            accessories: [copySocketButton])

        socketLabel.font = ConsoleTheme.Font.monoCode
        socketLabel.textColor = .labelColor
        socketLabel.lineBreakMode = .byTruncatingMiddle
        socketLabel.isSelectable = true
        socketLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let examples = NSTextField(wrappingLabelWithString:
            "PinShell show ./panel.html --watch --json\n" +
            "PinShell listen --json\n" +
            "PinShell eval 'document.querySelector(\"#status\").textContent = \"received\"'")
        examples.font = ConsoleTheme.Font.monoCode
        examples.textColor = .secondaryLabelColor
        examples.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let box = ConsoleInsetView(inset: NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12))
        let content = NSStackView(views: [socketLabel, examples])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 8
        content.translatesAutoresizingMaskIntoConstraints = false
        box.contentView.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: box.contentView.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: box.contentView.trailingAnchor),
            content.topAnchor.constraint(equalTo: box.contentView.topAnchor),
            content.bottomAnchor.constraint(equalTo: box.contentView.bottomAnchor),
        ])
        for view in [socketLabel, examples] {
            view.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }

        group.addContent(box)

        return group
    }

    // MARK: - 刷新

    func activate() {
        refresh()
    }

    func refresh() {
        let config = MCPClient.serverConfigurationJSON(executable: Self.executableURL)
        configText = config
        configLabel.stringValue = config
        socketLabel.stringValue = ControlEndpoint.socketURL().path
        socketLabel.toolTip = socketLabel.stringValue
        refreshClients()
    }

    // MARK: - 复制

    @objc private func copyConfig() {
        copy(configText, button: copyConfigButton,
             restore: NSLocalizedString("console.mcp.copyConfig", comment: ""))
    }

    @objc private func copySocket() {
        copy(socketLabel.stringValue, button: copySocketButton,
             restore: NSLocalizedString("console.mcp.copy", comment: ""))
    }

    private func copy(_ text: String, button: NSButton, restore: String) {
        copyStringToPasteboard(text)
        button.title = NSLocalizedString("console.events.copied", comment: "")
        copyResetWork?.cancel()
        let work = DispatchWorkItem { button.title = restore }
        copyResetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }
}
