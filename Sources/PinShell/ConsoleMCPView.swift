import AppKit
import PinShellCore

/// 控制台 MCP 2.0 页：stdio 服务配置、可用工具、控制通道。
final class ConsoleMCPView: NSView {
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
        let page = ConsoleScrollPage()
        page.translatesAutoresizingMaskIntoConstraints = false
        addSubview(page)
        NSLayoutConstraint.activate([
            page.leadingAnchor.constraint(equalTo: leadingAnchor),
            page.trailingAnchor.constraint(equalTo: trailingAnchor),
            page.topAnchor.constraint(equalTo: topAnchor),
            page.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
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
        let icon = NSImageView(image: NSImage(systemSymbolName: "network",
                                              accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .controlAccentColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 34),
            icon.heightAnchor.constraint(equalToConstant: 34),
        ])

        let title = NSTextField(labelWithString: NSLocalizedString("console.mcp.title", comment: ""))
        title.font = .systemFont(ofSize: 22, weight: .semibold)

        let chip = StatusChip()
        chip.update(text: NSLocalizedString("console.mcp.ready", comment: ""),
                    active: true, activeColor: .systemGreen,
                    symbol: "checkmark.circle.fill")

        let titleRow = NSStackView(views: [icon, title, NSView(), chip])
        titleRow.orientation = .horizontal
        titleRow.spacing = 10
        titleRow.alignment = .centerY

        let stack = NSStackView(views: [titleRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        titleRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    // MARK: - 客户端自动配置

    private func buildClientsCard() -> NSView {
        let refresh = makeSymbolButton(symbol: "arrow.clockwise",
                                       target: self,
                                       action: #selector(refreshClientsTapped))
        refresh.bezelStyle = .rounded
        refresh.controlSize = .small
        refresh.toolTip = NSLocalizedString("console.mcp.clients.refresh", comment: "")

        let card = MCPSectionCard(
            title: NSLocalizedString("console.mcp.clients.title", comment: ""),
            symbol: "person.2",
            accessories: [refresh])
        let stack = card.content

        let subtitle = NSTextField(wrappingLabelWithString:
            NSLocalizedString("console.mcp.clients.subtitle", comment: ""))
        subtitle.font = .systemFont(ofSize: 11.5)
        subtitle.textColor = .secondaryLabelColor

        stack.addArrangedSubview(subtitle)
        subtitle.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        for client in MCPClient.allCases {
            let row = buildClientRow(client)
            clientRows.append(row)
            stack.addArrangedSubview(row.view)
            row.view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let hint = NSTextField(wrappingLabelWithString:
            NSLocalizedString("console.mcp.clients.hint", comment: ""))
        hint.font = .systemFont(ofSize: 10.5)
        hint.textColor = .tertiaryLabelColor
        stack.addArrangedSubview(hint)
        hint.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        return card
    }

    private func buildClientRow(_ client: MCPClient) -> ClientRow {
        let name = NSTextField(labelWithString: client.displayName)
        name.font = .systemFont(ofSize: 12.5, weight: .medium)
        name.textColor = .labelColor

        let pathLabel = NSTextField(labelWithString: "")
        pathLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
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
        popup.font = .systemFont(ofSize: 11)
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
        return ClientRow(client: client, view: row, popup: popup,
                         chip: chip, pathLabel: pathLabel)
    }

    /// 客户端状态需要读取并解析可能很大的配置文件，放到后台计算，回主线程更新。
    private var clientsRefreshGeneration = 0

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

        DispatchQueue.global(qos: .userInitiated).async {
            let statuses = entries.map { $0.0.client.status(executable: executable, in: context) }
            DispatchQueue.main.async { [weak self] in
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
                        row.chip.update(text: statusKeys.detected, active: false,
                                        symbol: "minus.circle")
                        row.chip.toolTip = nil
                    } else if status.needsUpdate {
                        row.chip.update(text: statusKeys.stale, active: true,
                                        activeColor: .systemOrange,
                                        symbol: "exclamationmark.triangle.fill")
                        row.chip.toolTip = String(
                            format: NSLocalizedString("console.mcp.clients.staleHint", comment: ""),
                            executable.path)
                    } else if status.configured {
                        row.chip.update(text: statusKeys.configured, active: true,
                                        activeColor: .systemGreen,
                                        symbol: "checkmark.circle.fill")
                        row.chip.toolTip = url.path
                    } else {
                        row.chip.update(text: statusKeys.notConfigured, active: false,
                                        symbol: "slash.circle")
                        row.chip.toolTip = nil
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
        alert.addButton(withTitle: "OK")
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
        copyConfigButton.font = .systemFont(ofSize: 11)
        copyConfigButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copyConfigButton.imagePosition = .imageLeading
        copyConfigButton.target = self
        copyConfigButton.action = #selector(copyConfig)

        let card = MCPSectionCard(
            title: NSLocalizedString("console.mcp.config", comment: ""),
            symbol: "chevron.left.forwardslash.chevron.right",
            accessories: [copyConfigButton])
        let stack = card.content

        configLabel.isSelectable = true
        configLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        configLabel.textColor = .labelColor
        configLabel.maximumNumberOfLines = 0
        configLabel.lineBreakMode = .byWordWrapping

        let configBox = NSView()
        configBox.wantsLayer = true
        configBox.layer?.cornerRadius = 10
        configBox.layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.22).cgColor
        configLabel.translatesAutoresizingMaskIntoConstraints = false
        configBox.addSubview(configLabel)
        NSLayoutConstraint.activate([
            configLabel.leadingAnchor.constraint(equalTo: configBox.leadingAnchor, constant: 10),
            configLabel.trailingAnchor.constraint(equalTo: configBox.trailingAnchor, constant: -10),
            configLabel.topAnchor.constraint(equalTo: configBox.topAnchor, constant: 10),
            configLabel.bottomAnchor.constraint(equalTo: configBox.bottomAnchor, constant: -10),
        ])

        stack.addArrangedSubview(configBox)
        configBox.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        return card
    }

    private func buildToolsCard() -> NSView {
        let card = MCPSectionCard(
            title: NSLocalizedString("console.mcp.tools", comment: ""),
            symbol: "wrench.and.screwdriver")

        for tool in MCPToolSet.all {
            card.content.addArrangedSubview(toolRow(
                name: tool.name,
                symbol: Self.toolSymbols[tool.name] ?? "wrench",
                description: tool.description))
        }

        return card
    }

    private func buildPromptsCard() -> NSView {
        let card = MCPSectionCard(
            title: NSLocalizedString("console.mcp.prompts", comment: ""),
            symbol: "text.bubble")

        for prompt in MCPPromptCatalog.definitions {
            card.content.addArrangedSubview(toolRow(name: prompt.name,
                                                    symbol: "wand.and.stars",
                                                    description: prompt.description))
        }

        return card
    }

    private func toolRow(name: String, symbol: String, description: String) -> NSView {
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol,
                                              accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.heightAnchor.constraint(equalToConstant: 14),
        ])

        let nameLabel = NSTextField(labelWithString: name)
        nameLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        nameLabel.textColor = .labelColor

        let descLabel = NSTextField(labelWithString: description)
        descLabel.font = .systemFont(ofSize: 10.5)
        descLabel.textColor = .secondaryLabelColor
        descLabel.lineBreakMode = .byTruncatingTail

        let text = NSStackView(views: [nameLabel, descLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1

        let row = NSStackView(views: [icon, text])
        row.orientation = .horizontal
        row.spacing = 9
        row.alignment = .firstBaseline
        return row
    }

    private func buildChannelCard() -> NSView {
        copySocketButton.bezelStyle = .rounded
        copySocketButton.controlSize = .small
        copySocketButton.font = .systemFont(ofSize: 11)
        copySocketButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copySocketButton.imagePosition = .imageLeading
        copySocketButton.target = self
        copySocketButton.action = #selector(copySocket)

        let card = MCPSectionCard(
            title: NSLocalizedString("console.mcp.channel", comment: ""),
            symbol: "terminal",
            accessories: [copySocketButton])
        let stack = card.content

        socketLabel.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        socketLabel.textColor = .labelColor
        socketLabel.lineBreakMode = .byTruncatingMiddle
        socketLabel.isSelectable = true
        socketLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let examples = NSTextField(wrappingLabelWithString:
            "PinShell show ./panel.html --watch --json\n" +
            "PinShell listen --json\n" +
            "PinShell eval 'document.querySelector(\"#status\").textContent = \"received\"'")
        examples.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        examples.textColor = .secondaryLabelColor

        stack.addArrangedSubview(socketLabel)
        stack.addArrangedSubview(examples)
        for view in [socketLabel, examples] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        return card
    }

    // MARK: - 刷新

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
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        button.title = NSLocalizedString("console.events.copied", comment: "")
        copyResetWork?.cancel()
        let work = DispatchWorkItem { button.title = restore }
        copyResetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }
}

/// MCP 页的分区卡片：标题行常驻，内容默认折叠，点击左侧箭头展开/收起。
private final class MCPSectionCard: NSView {
    private let toggleButton = NSButton()
    private let body = NSStackView()
    private var bodyWidthConstraint: NSLayoutConstraint?
    private var expanded = false

    /// 内容区。调用方把分区内容加到这里，并自行约束宽度。
    var content: NSStackView { body }

    init(title: String, symbol: String, accessories: [NSView] = []) {
        super.init(frame: .zero)

        toggleButton.isBordered = false
        toggleButton.imageScaling = .scaleProportionallyDown
        toggleButton.contentTintColor = .secondaryLabelColor
        toggleButton.target = self
        toggleButton.action = #selector(toggle)
        toggleButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            toggleButton.widthAnchor.constraint(equalToConstant: 14),
            toggleButton.heightAnchor.constraint(equalToConstant: 14),
        ])

        let header = NSStackView(views: [
            toggleButton,
            makeSectionLabel(title, symbol: symbol),
            NSView(),
        ] + accessories)
        header.orientation = .horizontal
        header.spacing = 8
        header.alignment = .centerY

        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 10
        body.isHidden = true

        let stack = NSStackView(views: [header, body])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        let card = GlassCard()
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)
        card.contentView.addSubview(stack)
        // 初始折叠，展开时再激活宽度约束；隐藏期间部分系统会把视图移出层级。
        bodyWidthConstraint = body.widthAnchor.constraint(equalTo: stack.widthAnchor)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: card.contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor),

            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        updateToggle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func toggle() {
        expanded.toggle()
        body.isHidden = !expanded
        if expanded {
            // 隐藏的 arranged subview 可能被 stack 摘下，重新展开时确保宽度约束在位。
            bodyWidthConstraint?.isActive = true
        }
        updateToggle()
    }

    private static let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10,
                                                                         weight: .semibold)

    private func updateToggle() {
        let name = expanded ? "chevron.down" : "chevron.right"
        toggleButton.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(Self.symbolConfiguration)
        let hint = NSLocalizedString(expanded ? "console.mcp.collapse" : "console.mcp.expand",
                                     comment: "")
        toggleButton.toolTip = hint
        toggleButton.setAccessibilityLabel(hint)
    }
}
