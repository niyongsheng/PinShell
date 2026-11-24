import AppKit
import PinShellCore

/// 控制台「快捷键」页：分组列出全局与控制台快捷键，点击右侧按钮重新录制。
final class ConsoleShortcutsView: NSView, ConsoleServicePage {
    private let notice = ConsoleNoticeView(tone: .warning)
    private var recorders: [ShortcutAction: ShortcutRecorderButton] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(shortcutsChanged),
                                               name: .pinshellShortcutsChanged,
                                               object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func activate() {
        refreshValues()
    }

    // MARK: - 装配

    private func build() {
        let page = SettingsPageView(spacing: ConsoleTheme.Space.lg)
        page.pinEdges(to: self)

        let header = SettingsPageHeaderView(
            title: NSLocalizedString("console.shortcuts.title", comment: ""))

        notice.isHidden = true

        let globalGroup = makeGroup(
            title: NSLocalizedString("console.shortcuts.global.title", comment: ""),
            footer: NSLocalizedString("console.shortcuts.global.footer", comment: ""),
            actions: ShortcutAction.allCases.filter { $0.scope == .global })

        let resetTile = SettingsIconTile(symbol: "arrow.counterclockwise",
                                         tint: .systemGray,
                                         size: 22)
        let resetGroup = SettingsGroupView()
        resetGroup.addRow(SettingsRowView(
            title: NSLocalizedString("console.shortcuts.reset", comment: ""),
            subtitle: NSLocalizedString("console.shortcuts.resetSubtitle", comment: ""),
            leading: resetTile,
            onClick: { [weak self] in self?.resetAll() }))

        for view in [header, notice, globalGroup, resetGroup] {
            page.addSection(view)
        }
    }

    private func makeGroup(title: String,
                           footer: String,
                           actions: [ShortcutAction]) -> SettingsGroupView {
        let group = SettingsGroupView(title: title, footer: footer)
        for action in actions {
            group.addRow(makeRow(for: action))
        }
        return group
    }

    private func makeRow(for action: ShortcutAction) -> NSView {
        let tile = SettingsIconTile(symbol: action.symbol, tint: action.tint, size: 22)

        let recorder = ShortcutRecorderButton()
        recorder.displayCombo = ShortcutStore.shared.combo(for: action)
        recorder.setAccessibilityLabel(String(
            format: NSLocalizedString("console.shortcuts.recorderLabel", comment: ""),
            action.title))
        recorder.onCommit = { [weak self] combo in
            self?.commit(combo, for: action)
        }
        recorder.onFinish = { [weak self] in
            self?.refreshValues()
        }
        recorders[action] = recorder

        return SettingsRowView(title: action.title,
                               subtitle: action.subtitle,
                               leading: tile,
                               accessory: recorder)
    }

    // MARK: - 刷新

    private func refreshValues() {
        for (action, recorder) in recorders {
            recorder.displayCombo = ShortcutStore.shared.combo(for: action)
        }
        updateRegistrationNotice()
    }

    @objc private func shortcutsChanged() {
        refreshValues()
    }

    /// 全局热键可能被系统或其他应用占用：Carbon 注册失败时在页面顶部说明原因。
    private func updateRegistrationNotice() {
        let failed = ShortcutAction.allCases.filter {
            $0.scope == .global && GlobalHotKeyCenter.shared.registrationFailed(for: $0)
        }
        guard let first = failed.first,
              let combo = ShortcutStore.shared.combo(for: first) else {
            notice.isHidden = true
            return
        }
        showNotice(String(format: NSLocalizedString("console.shortcuts.notice.unavailable",
                                                    comment: ""),
                          combo.displayString))
    }

    // MARK: - 录制结果

    private func commit(_ combo: ShortcutCombo?,
                        for action: ShortcutAction) -> ShortcutStore.StoreError? {
        let previous = ShortcutStore.shared.combo(for: action)
        do {
            try ShortcutStore.shared.setCombo(combo, for: action)
            // 全局热键可能被系统占用：注册失败时回滚，避免留下不可用的配置。
            if action.scope == .global, combo != nil,
               GlobalHotKeyCenter.shared.registrationFailed(for: action) {
                try? ShortcutStore.shared.setCombo(previous, for: action)
                showNotice(message(for: .unavailable))
                return .unavailable
            }
            notice.isHidden = true
            refreshValues()
            return nil
        } catch let error as ShortcutStore.StoreError {
            showNotice(message(for: error))
            return error
        } catch {
            showNotice(error.localizedDescription)
            return .needsModifier
        }
    }

    private func message(for error: ShortcutStore.StoreError) -> String {
        switch error {
        case .needsModifier:
            return NSLocalizedString("console.shortcuts.error.needsModifier", comment: "")
        case .conflict(let other):
            return String(format: NSLocalizedString("console.shortcuts.error.conflict",
                                                    comment: ""),
                          other.title)
        case .unavailable:
            return NSLocalizedString("console.shortcuts.error.unavailable", comment: "")
        }
    }

    private func showNotice(_ text: String) {
        notice.configure(text: text)
        notice.isHidden = false
    }

    private func resetAll() {
        ShortcutStore.shared.resetAll()
        notice.isHidden = true
        refreshValues()
    }
}

// MARK: - 快捷键录制按钮

/// 快捷键录制控件：点击进入录制，Esc 取消，Delete 清除，其余组合写入配置。
final class ShortcutRecorderButton: NSButton {
    /// 录制期间控制台导航与全局热键都不响应，避免边录边触发。
    private(set) static var activeRecorder: ShortcutRecorderButton?

    /// 写入组合（nil = 清除）；返回错误时继续录制并保持按钮状态。
    var onCommit: ((ShortcutCombo?) -> ShortcutStore.StoreError?)?
    var onFinish: (() -> Void)?

    var displayCombo: ShortcutCombo? {
        didSet {
            guard !isRecording else { return }
            updateTitle()
        }
    }

    private var isRecording = false
    private var monitor: Any?
    private var windowObservers: [NSObjectProtocol] = []

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        bezelStyle = .rounded
        controlSize = .regular
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(buttonClicked)
        focusRingType = .none
        widthAnchor.constraint(greaterThanOrEqualToConstant: 104).isActive = true
        updateTitle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        windowObservers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: 录制

    @objc private func buttonClicked() {
        if isRecording {
            cancelRecording()
        } else {
            beginRecording()
        }
    }

    private func beginRecording() {
        guard !isRecording else { return }
        // 同时只保留一个录制按钮，避免两个本地键盘监听叠加。
        if let active = Self.activeRecorder, active !== self {
            active.cancelRecording()
        }
        Self.activeRecorder = self
        ShortcutDispatcher.shared.setRecording(true)
        isRecording = true
        window?.makeFirstResponder(self)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecording else { return event }
            self.handle(event)
            return nil
        }
        updateTitle()
    }

    private func handle(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        let modifiers = ShortcutModifiers(eventFlags: event.modifierFlags)

        // 无修饰键的 Esc / Delete 是录制控制键，不写入配置。
        if event.keyCode == 53, modifiers.isEmpty {
            cancelRecording()
            return
        }
        if event.keyCode == 51 || event.keyCode == 117, modifiers.isEmpty {
            commit(nil)
            return
        }

        guard let combo = ShortcutCombo(keyCode: event.keyCode,
                                        modifiers: modifiers,
                                        characters: event.charactersIgnoringModifiers ?? "")
        else { return }
        commit(combo)
    }

    private func commit(_ combo: ShortcutCombo?) {
        guard let onCommit else { return }
        guard onCommit(combo) == nil else { return }   // 冲突/缺少修饰键：保持录制状态
        finishRecording()
    }

    func cancelRecording() {
        finishRecording()
    }

    private func finishRecording() {
        guard isRecording else { return }
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if Self.activeRecorder === self {
            Self.activeRecorder = nil
            ShortcutDispatcher.shared.setRecording(false)
        }
        updateTitle()
        onFinish?()
    }

    // MARK: 外观

    private func updateTitle() {
        let text = isRecording
            ? NSLocalizedString("console.shortcuts.recording", comment: "")
            : (displayCombo?.displayString
                ?? NSLocalizedString("console.shortcuts.unset", comment: ""))
        let color: NSColor
        if isRecording {
            color = ConsoleTheme.Color.contrastingLabel(on: ConsoleTheme.Color.accent)
        } else if displayCombo == nil {
            color = .secondaryLabelColor
        } else {
            color = .labelColor
        }
        attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: color,
        ])
        bezelColor = isRecording ? ConsoleTheme.Color.accent : nil
        setAccessibilityValue(text)
    }

    // MARK: 窗口生命周期

    /// 窗口失去焦点或关闭时结束录制，避免本地键盘监听残留。
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeWindowObservers()
        guard let window else {
            cancelRecording()
            return
        }
        let center = NotificationCenter.default
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            windowObservers.append(center.addObserver(forName: name,
                                                      object: window,
                                                      queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.cancelRecording()
                }
            })
        }
    }

    private func removeWindowObservers() {
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers.removeAll()
    }
}
