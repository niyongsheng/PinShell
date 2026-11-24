import AppKit

/// 控制台「通用」页：模板库来源管理与隐私设置。
final class ConsoleGeneralView: NSView, ConsoleServicePage {
    private let service: TemplateLibraryService
    private let sourcesContainer = NSView()
    private let sourcesStack = NSStackView()
    private let analyticsSwitch = NSSwitch()
    private var addSourceSheet: AddTemplateLibrarySheetController?
    private var lastStatuses: [TemplateLibraryService.SourceStatus]?
    private var lastRefreshing = false

    init(service: TemplateLibraryService) {
        self.service = service
        super.init(frame: .zero)
        build()
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// 控制台打开时已加载目录；这里只刷新当前状态，避免重复扫描本地模板。
    func activate() {
        refresh()
    }

    func refresh() {
        rebuildSourcesIfNeeded()
    }

    // MARK: - 装配

    private func build() {
        let page = SettingsPageView(spacing: ConsoleTheme.Space.lg)
        page.pinEdges(to: self)

        let header = SettingsPageHeaderView(
            title: NSLocalizedString("console.general.title", comment: ""))

        sourcesStack.orientation = .vertical
        sourcesStack.alignment = .leading
        sourcesStack.spacing = 0
        sourcesStack.pinEdges(to: sourcesContainer)

        let appearance = buildAppearanceGroup()
        let privacy = buildPrivacyGroup()

        for view in [header, appearance, sourcesContainer, privacy] {
            page.addSection(view)
        }
    }

    private func buildAppearanceGroup() -> NSView {
        let control = NSSegmentedControl(
            labels: AppAppearance.allCases.map { appearanceKey(for: $0) },
            trackingMode: .selectOne,
            target: self,
            action: #selector(appearanceChanged(_:)))
        control.segmentStyle = .rounded
        control.selectedSegment = AppAppearance.allCases.firstIndex(of: AppState.appearance) ?? 0
        control.setAccessibilityLabel(
            NSLocalizedString("console.general.appearance.theme", comment: ""))

        let tile = SettingsIconTile(symbol: "circle.lefthalf.filled",
                                    tint: ConsoleTheme.Color.info,
                                    size: 22)
        let row = SettingsRowView(
            title: NSLocalizedString("console.general.appearance.theme", comment: ""),
            subtitle: NSLocalizedString("console.general.appearance.subtitle", comment: ""),
            leading: tile,
            accessory: control)

        let group = SettingsGroupView(
            title: NSLocalizedString("console.general.appearance.title", comment: ""))
        group.addRow(row)
        return group
    }

    private func appearanceKey(for appearance: AppAppearance) -> String {
        let key: String
        switch appearance {
        case .system: key = "console.general.appearance.auto"
        case .light: key = "console.general.appearance.light"
        case .dark: key = "console.general.appearance.dark"
        }
        return NSLocalizedString(key, comment: "")
    }

    private func buildPrivacyGroup() -> NSView {
        analyticsSwitch.state = Analytics.shared.isEnabled ? .on : .off
        analyticsSwitch.target = self
        analyticsSwitch.action = #selector(analyticsToggled(_:))
        analyticsSwitch.setAccessibilityLabel(
            NSLocalizedString("console.general.privacy.analytics", comment: ""))

        let tile = SettingsIconTile(symbol: "chart.bar.fill",
                                    tint: NSColor.systemPurple,
                                    size: 22)
        let row = SettingsRowView(
            title: NSLocalizedString("console.general.privacy.analytics", comment: ""),
            subtitle: NSLocalizedString("console.general.privacy.text", comment: ""),
            leading: tile,
            accessory: analyticsSwitch)

        let group = SettingsGroupView(
            title: NSLocalizedString("console.general.privacy.title", comment: ""))
        group.addRow(row)
        return group
    }

    // MARK: - 来源列表

    private func rebuildSourcesIfNeeded() {
        let statuses = service.sourceStatuses
        let refreshing = service.isRefreshing
        guard statuses != lastStatuses || refreshing != lastRefreshing else { return }
        lastStatuses = statuses
        lastRefreshing = refreshing

        for view in sourcesStack.arrangedSubviews {
            sourcesStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let group = SettingsGroupView(
            title: NSLocalizedString("console.general.library.title", comment: ""),
            footer: NSLocalizedString("console.general.library.footer", comment: ""))
        for status in statuses {
            group.addRow(makeSourceRow(status))
        }
        group.addRow(makeAddRow())
        sourcesStack.addArrangedSubview(group)
        group.widthAnchor.constraint(equalTo: sourcesStack.widthAnchor).isActive = true
    }

    private func makeSourceRow(_ status: TemplateLibraryService.SourceStatus) -> NSView {
        let source = status.source
        let title = source.localizedTitle
        let (value, valueColor) = statusText(for: status)
        let tile = SettingsIconTile(
            symbol: source.isOfficial ? "shippingbox.fill" : "globe",
            tint: source.isOfficial ? ConsoleTheme.Color.positive : ConsoleTheme.Color.info,
            size: 22)

        var accessory: NSView?
        if !source.isOfficial {
            let remove = SourceRemoveButton(target: self,
                                             action: #selector(removeSourceTapped(_:)))
            configureIconButton(
                remove,
                symbol: "minus.circle",
                accessibilityLabel: NSLocalizedString("console.general.library.remove", comment: ""))
            remove.source = source
            remove.toolTip = NSLocalizedString("console.general.library.removeHint", comment: "")
            accessory = remove
        }

        let subtitle = status.error.map {
            "\(source.url.absoluteString)\n\($0)"
        } ?? source.url.absoluteString
        let row = SettingsRowView(title: title,
                                  subtitle: subtitle,
                                  value: value,
                                  valueColor: valueColor,
                                  leading: tile,
                                  accessory: accessory)
        var tips = [source.url.absoluteString]
        if let error = status.error {
            tips.append(error)
        }
        if status.isReadOnly {
            tips.append(NSLocalizedString("console.general.library.status.offlineHint",
                                          comment: ""))
        }
        if !status.skippedTemplateIDs.isEmpty {
            tips.append(String(
                format: NSLocalizedString("console.general.library.status.skippedHint",
                                          comment: ""),
                status.skippedTemplateIDs.joined(separator: ", ")))
        }
        row.toolTip = tips.count > 1 ? tips.joined(separator: "\n") : nil
        return row
    }

    private func makeAddRow() -> NSView {
        let tile = SettingsIconTile(symbol: "plus",
                                    tint: ConsoleTheme.Color.info,
                                    size: 22)
        return SettingsRowView(
            title: NSLocalizedString("console.general.library.add", comment: ""),
            subtitle: NSLocalizedString("console.general.library.addSubtitle", comment: ""),
            leading: tile,
            onClick: { [weak self] in self?.presentAddSheet() })
    }

    private func statusText(
        for status: TemplateLibraryService.SourceStatus
    ) -> (String, NSColor) {
        guard status.isLoaded else {
            if status.error != nil {
                return (NSLocalizedString("console.general.library.status.failed", comment: ""),
                        ConsoleTheme.Color.warning)
            }
            return (NSLocalizedString("console.general.library.status.loading", comment: ""),
                    .secondaryLabelColor)
        }

        let formatKey = status.isReadOnly
            ? "console.general.library.status.offline"
            : "console.general.library.status.count"
        var text = String(format: NSLocalizedString(formatKey, comment: ""),
                          status.templateCount)
        if status.skippedCount > 0 {
            text += " · " + String(format: NSLocalizedString(
                "console.general.library.status.skipped", comment: ""), status.skippedCount)
        }
        let needsAttention = status.isReadOnly
            || status.error != nil
            || !status.skippedTemplateIDs.isEmpty
        return (text, needsAttention ? ConsoleTheme.Color.warning : .secondaryLabelColor)
    }

    // MARK: - 动作

    private func presentAddSheet() {
        guard let window else { return }
        let sheet = AddTemplateLibrarySheetController()
        sheet.onCheck = { [weak self] raw in
            guard let self else { return .failure("") }
            do {
                let preview = try await self.service.previewSource(raw)
                return self.checkOutcome(for: preview)
            } catch {
                return .failure(self.message(for: error))
            }
        }
        sheet.onAdd = { [weak self] raw in
            guard let self else { return "" }
            do {
                try self.service.addSource(raw)
                Task { @MainActor in
                    await self.service.refresh()
                }
                return nil
            } catch {
                return self.message(for: error)
            }
        }
        sheet.onDismiss = { [weak self] in self?.addSourceSheet = nil }
        addSourceSheet = sheet
        sheet.present(in: window)
    }

    private func checkOutcome(
        for preview: TemplateLibraryService.SourcePreview
    ) -> AddTemplateLibrarySheetController.CheckOutcome {
        if let error = preview.fetchError {
            let title = NSLocalizedString(
                "console.general.library.conflict.unreadableTitle", comment: "")
            let detail = String(
                format: NSLocalizedString(
                    "console.general.library.conflict.unreadableDetail", comment: ""),
                error)
            return .confirmation(title: title, detail: detail)
        }
        guard !preview.conflicts.isEmpty else { return .clear }

        let title = String(
            format: NSLocalizedString("console.general.library.conflict.title", comment: ""),
            preview.conflicts.count)
        let lines = preview.conflicts.map { conflict in
            String(
                format: NSLocalizedString("console.general.library.conflict.item", comment: ""),
                conflict.templateName,
                conflict.templateID,
                conflict.existingSourceName)
        }
        let intro = NSLocalizedString("console.general.library.conflict.intro", comment: "")
        return .confirmation(title: title,
                             detail: intro + "\n\n" + lines.joined(separator: "\n"))
    }

    @objc private func removeSourceTapped(_ sender: SourceRemoveButton) {
        guard let source = sender.source else { return }
        service.removeSource(source)
    }

    @objc private func analyticsToggled(_ sender: NSSwitch) {
        Analytics.shared.isEnabled = sender.state == .on
    }

    @objc private func appearanceChanged(_ sender: NSSegmentedControl) {
        let index = sender.selectedSegment
        guard AppAppearance.allCases.indices.contains(index) else { return }
        AppState.appearance = AppAppearance.allCases[index]
        AppState.appearance.apply()
    }

    private func message(for error: Error) -> String {
        guard let error = error as? TemplateLibraryPreferences.AddCatalogError else {
            return error.localizedDescription
        }
        let key: String
        switch error {
        case .empty: key = "console.general.library.error.empty"
        case .invalid: key = "console.general.library.error.invalid"
        case .insecure: key = "console.general.library.error.insecure"
        case .duplicate: key = "console.general.library.error.duplicate"
        }
        return NSLocalizedString(key, comment: "")
    }
}

// MARK: - 来源移除按钮

private final class SourceRemoveButton: NSButton {
    var source: TemplateLibrarySource?

    init(target: AnyObject?, action: Selector) {
        super.init(frame: .zero)
        self.target = target
        self.action = action
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

// MARK: - 添加模板库弹窗

/// 添加模板库地址的小弹窗：先异步检查 id 冲突，冲突时列出会被跳过的模板，
/// 再次点击「仍然添加」才写入偏好。
private final class AddTemplateLibrarySheetController: NSWindowController, NSTextFieldDelegate {
    enum CheckOutcome {
        case clear
        case confirmation(title: String, detail: String)
        case failure(String)
    }

    /// 异步预检：规范化地址、拉取候选目录并计算冲突；不会写入偏好。
    var onCheck: ((String) async -> CheckOutcome)?
    /// 确认后写入偏好；返回错误文案时不关闭弹窗。
    var onAdd: ((String) -> String?)?
    var onDismiss: (() -> Void)?

    private let urlField = NSTextField(string: "")
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let spinner = NSProgressIndicator()
    private let detailScrollView = NSScrollView()
    private let detailTextView = NSTextView()
    private let addButton = NSButton(title: "", target: nil, action: nil)
    private var detailHeight: NSLayoutConstraint?
    private var pendingConfirmation = false
    private var lastCheckedValue = ""
    private var isChecking = false

    private static let normalHeight: CGFloat = 250
    private static let expandedHeight: CGFloat = 430

    private enum StatusTone {
        case normal, warning, error
    }

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460,
                                                  height: Self.normalHeight),
                              styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.title = NSLocalizedString("console.general.library.addTitle", comment: "")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func present(in parent: NSWindow) {
        guard let window, window.sheetParent == nil else { return }
        parent.beginSheet(window)
        window.makeFirstResponder(urlField)
    }

    private func build() {
        guard let window else { return }
        let root = ConsoleBackgroundView()
        window.contentView = root

        let title = NSTextField(labelWithString:
            NSLocalizedString("console.general.library.addTitle", comment: ""))
        title.font = ConsoleTheme.Font.editorTitle
        title.textColor = .labelColor

        let info = NSTextField(wrappingLabelWithString:
            NSLocalizedString("console.general.library.addInfo", comment: ""))
        info.font = ConsoleTheme.Font.body
        info.textColor = .secondaryLabelColor
        info.maximumNumberOfLines = 3
        info.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        urlField.placeholderString = NSLocalizedString(
            "console.general.library.urlPlaceholder", comment: "")
        urlField.controlSize = .large
        urlField.font = .systemFont(ofSize: 13)
        urlField.delegate = self
        urlField.translatesAutoresizingMaskIntoConstraints = false
        urlField.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.isHidden = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            spinner.widthAnchor.constraint(equalToConstant: 16),
            spinner.heightAnchor.constraint(equalToConstant: 16),
        ])

        statusLabel.font = ConsoleTheme.Font.caption
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 3
        statusLabel.isHidden = true
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let statusRow = NSStackView(views: [spinner, statusLabel])
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 8
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        detailTextView.isEditable = false
        detailTextView.isSelectable = true
        detailTextView.drawsBackground = false
        detailTextView.font = ConsoleTheme.Font.caption
        detailTextView.textColor = .secondaryLabelColor
        detailTextView.textContainerInset = NSSize(width: 2, height: 6)
        detailTextView.minSize = NSSize(width: 0, height: 0)
        detailTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                        height: CGFloat.greatestFiniteMagnitude)
        detailTextView.isVerticallyResizable = true
        detailTextView.isHorizontallyResizable = false
        detailTextView.autoresizingMask = [.width]
        detailTextView.textContainer?.containerSize = NSSize(
            width: 0, height: CGFloat.greatestFiniteMagnitude)
        detailTextView.textContainer?.widthTracksTextView = true

        detailScrollView.documentView = detailTextView
        detailScrollView.hasVerticalScroller = true
        detailScrollView.drawsBackground = false
        detailScrollView.borderType = .noBorder
        detailScrollView.isHidden = true
        detailScrollView.translatesAutoresizingMaskIntoConstraints = false
        let height = detailScrollView.heightAnchor.constraint(equalToConstant: 0)
        height.isActive = true
        detailHeight = height

        let cancel = NSButton(title: NSLocalizedString("console.general.library.cancel", comment: ""),
                              target: self, action: #selector(cancel))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"

        addButton.title = NSLocalizedString("console.general.library.addConfirm", comment: "")
        addButton.target = self
        addButton.action = #selector(submit)
        addButton.bezelStyle = .rounded
        addButton.keyEquivalent = "\r"
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        addButton.imagePosition = .imageLeading
        configureConsoleButton(addButton,
                               title: NSLocalizedString("console.general.library.addConfirm",
                                                        comment: ""),
                               symbol: "plus",
                               style: .primary)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [spacer, cancel, addButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.alignment = .centerY

        let flexible = NSView()
        flexible.setContentHuggingPriority(.defaultLow, for: .vertical)
        flexible.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        let stack = NSStackView(views: [title, info, urlField, statusRow,
                                        detailScrollView, flexible, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -22),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
            info.widthAnchor.constraint(equalTo: stack.widthAnchor),
            urlField.widthAnchor.constraint(equalTo: stack.widthAnchor),
            statusRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            detailScrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    // MARK: 提交

    @objc private func submit() {
        guard !isChecking else { return }
        if pendingConfirmation {
            addSource()
        } else {
            // 先读取字段值再禁用控件：AX/输入法可能尚未提交，禁用会丢掉未提交内容。
            beginCheck(value: urlField.stringValue)
        }
    }

    private func beginCheck(value: String) {
        guard let onCheck else { return }
        Task { @MainActor in
            isChecking = true
            setCheckingUI(true)
            let outcome = await onCheck(value)
            isChecking = false
            guard window?.sheetParent != nil else { return }
            setCheckingUI(false)
            handle(outcome, checkedValue: value)
        }
    }

    private func handle(_ outcome: CheckOutcome, checkedValue: String) {
        switch outcome {
        case .clear:
            addSource()
        case .failure(let message):
            setStatus(message, tone: .error)
            window?.makeFirstResponder(urlField)
        case .confirmation(let title, let detail):
            pendingConfirmation = true
            lastCheckedValue = checkedValue
            setStatus(title, tone: .warning)
            showDetail(detail)
            updateAddButton(key: "console.general.library.addAnyway")
            window?.makeFirstResponder(urlField)
        }
    }

    private func addSource() {
        guard let onAdd else { return }
        if let message = onAdd(urlField.stringValue) {
            resetConfirmation()
            setStatus(message, tone: .error)
            window?.makeFirstResponder(urlField)
        } else {
            finish()
        }
    }

    @objc private func cancel() {
        finish()
    }

    private func finish() {
        if let window {
            window.sheetParent?.endSheet(window)
        }
        onDismiss?()
    }

    // MARK: 状态

    private func setCheckingUI(_ checking: Bool) {
        urlField.isEnabled = !checking
        addButton.isEnabled = !checking
        if checking {
            spinner.isHidden = false
            spinner.startAnimation(nil)
            setStatus(NSLocalizedString("console.general.library.checking", comment: ""),
                      tone: .normal)
        } else {
            spinner.stopAnimation(nil)
            spinner.isHidden = true
        }
    }

    private func setStatus(_ text: String?, tone: StatusTone) {
        statusLabel.stringValue = text ?? ""
        statusLabel.isHidden = (text ?? "").isEmpty
        switch tone {
        case .normal: statusLabel.textColor = .secondaryLabelColor
        case .warning: statusLabel.textColor = ConsoleTheme.Color.warning
        case .error: statusLabel.textColor = ConsoleTheme.Color.destructive
        }
    }

    private func showDetail(_ detail: String) {
        detailTextView.string = detail
        detailTextView.scrollRangeToVisible(NSRange(location: 0, length: 0))
        detailScrollView.isHidden = false
        detailHeight?.constant = 140
        window?.setContentSize(NSSize(width: 460, height: Self.expandedHeight))
    }

    private func hideDetail() {
        detailTextView.string = ""
        detailScrollView.isHidden = true
        detailHeight?.constant = 0
        window?.setContentSize(NSSize(width: 460, height: Self.normalHeight))
    }

    private func resetConfirmation() {
        pendingConfirmation = false
        lastCheckedValue = ""
        hideDetail()
        setStatus(nil, tone: .normal)
        updateAddButton(key: "console.general.library.addConfirm")
    }

    private func updateAddButton(key: String) {
        let title = NSLocalizedString(key, comment: "")
        addButton.title = title
        addButton.setAccessibilityLabel(title)
    }

    func controlTextDidChange(_ obj: Notification) {
        guard pendingConfirmation, urlField.stringValue != lastCheckedValue else { return }
        resetConfirmation()
    }
}
