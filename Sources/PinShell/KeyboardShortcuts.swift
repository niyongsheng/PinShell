import AppKit
import Carbon.HIToolbox
import PinShellCore

extension Notification.Name {
    /// 快捷键配置变化：状态栏菜单、控制台按键分发与全局热键都以此为准。
    static let pinshellShortcutsChanged = Notification.Name("PinShell.shortcutsChanged")
}

// MARK: - 动作

enum ShortcutScope {
    /// 任意应用中生效，通过 Carbon 全局热键注册。
    case global
    /// 仅在控制台窗口获得焦点时生效。
    case console
}

/// 可配置快捷键的动作。rawValue 同时作为本地化 key 与持久化存储 key。
enum ShortcutAction: String, CaseIterable {
    case toggleOverlay
    case togglePassthrough
    case openConsole

    case showTemplates
    case showMCP
    case showAbout
    case showLibrary
    case showGeneral
    case editTemplate

    var scope: ShortcutScope {
        switch self {
        case .toggleOverlay, .togglePassthrough, .openConsole:
            return .global
        default:
            return .console
        }
    }

    /// 控制台导航动作对应的服务页；与侧边栏共用同一目的地定义。
    var page: ConsolePage? {
        switch self {
        case .showLibrary: return .library
        case .showGeneral: return .general
        case .showMCP: return .mcp
        case .showAbout: return .about
        default: return nil
        }
    }

    /// 默认组合。全局键刻意避开系统常用快捷键（如 ⌥⌘H）。
    var defaultCombo: ShortcutCombo {
        switch self {
        case .toggleOverlay:
            return ShortcutCombo(keyCode: 35, modifiers: [.control, .option], key: "p")
        case .togglePassthrough:
            return ShortcutCombo(keyCode: 17, modifiers: [.control, .option], key: "t")
        case .openConsole:
            return ShortcutCombo(keyCode: 8, modifiers: [.control, .option], key: "c")
        case .showTemplates:
            return ShortcutCombo(keyCode: 18, modifiers: [.command], key: "1")
        case .showMCP:
            return ShortcutCombo(keyCode: 19, modifiers: [.command], key: "2")
        case .showAbout:
            return ShortcutCombo(keyCode: 20, modifiers: [.command], key: "3")
        case .showLibrary:
            return ShortcutCombo(keyCode: 21, modifiers: [.command], key: "4")
        case .showGeneral:
            return ShortcutCombo(keyCode: 23, modifiers: [.command], key: "5")
        case .editTemplate:
            return ShortcutCombo(keyCode: 14, modifiers: [.command], key: "e")
        }
    }

    var title: String {
        NSLocalizedString("console.shortcuts.action.\(rawValue)", comment: "")
    }

    var subtitle: String? {
        switch self {
        case .toggleOverlay, .togglePassthrough, .openConsole:
            return NSLocalizedString("console.shortcuts.action.\(rawValue).subtitle", comment: "")
        default:
            return nil
        }
    }

    var symbol: String {
        if let page { return page.symbol }
        switch self {
        case .toggleOverlay: return "rectangle.on.rectangle"
        case .togglePassthrough: return "cursorarrow.rays"
        case .openConsole: return "macwindow"
        case .showTemplates: return "square.stack"
        case .editTemplate: return "slider.horizontal.3"
        default: return "square.grid.2x2"
        }
    }

    var tint: NSColor {
        switch self {
        case .toggleOverlay: return .systemBlue
        case .togglePassthrough: return .systemOrange
        case .openConsole: return .systemTeal
        case .showTemplates: return .systemBlue
        case .showMCP: return .systemGreen
        case .showAbout: return .systemIndigo
        case .showLibrary: return .systemPurple
        case .showGeneral: return .systemGray
        case .editTemplate: return .systemOrange
        }
    }
}

// MARK: - 偏好存储

/// 快捷键配置：UserDefaults 只存与默认值不同的覆盖项与「已清除」标记，
/// 未配置的动作始终跟随代码里的默认值。
@MainActor
final class ShortcutStore {
    static let shared = ShortcutStore()

    enum StoreError: Error, Equatable {
        case needsModifier
        case conflict(ShortcutAction)
        /// 全局热键被系统或其他应用占用，Carbon 注册失败。
        case unavailable
    }

    private struct Persisted: Codable {
        var combos: [String: ShortcutCombo] = [:]
        var disabled: Set<String> = []
    }

    private static let defaultsKey = "keyboardShortcuts"
    private var persisted: Persisted

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let value = try? JSONDecoder().decode(Persisted.self, from: data) {
            persisted = value
        } else {
            persisted = Persisted()
        }
    }

    /// 当前生效的组合；nil 表示该动作未设置快捷键。
    func combo(for action: ShortcutAction) -> ShortcutCombo? {
        if persisted.disabled.contains(action.rawValue) { return nil }
        if let stored = persisted.combos[action.rawValue], stored.isValid { return stored }
        return action.defaultCombo
    }

    /// 写入组合；nil 表示清除。校验失败时不做任何改动。
    func setCombo(_ combo: ShortcutCombo?, for action: ShortcutAction) throws {
        if let combo {
            guard combo.isValid else { throw StoreError.needsModifier }
            if let other = conflictingAction(for: combo, excluding: action) {
                throw StoreError.conflict(other)
            }
        }

        if let combo {
            persisted.combos[action.rawValue] = combo
            persisted.disabled.remove(action.rawValue)
        } else {
            persisted.combos.removeValue(forKey: action.rawValue)
            persisted.disabled.insert(action.rawValue)
        }
        save()
        if action.scope == .global {
            GlobalHotKeyCenter.shared.sync()
        }
        NotificationCenter.default.post(name: .pinshellShortcutsChanged, object: self)
    }

    func resetAll() {
        persisted = Persisted()
        save()
        GlobalHotKeyCenter.shared.sync()
        NotificationCenter.default.post(name: .pinshellShortcutsChanged, object: self)
    }

    private func conflictingAction(for combo: ShortcutCombo,
                                    excluding action: ShortcutAction) -> ShortcutAction? {
        ShortcutAction.allCases.first {
            $0 != action && self.combo(for: $0)?.isEquivalent(to: combo) == true
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}

// MARK: - 统一派发

/// 所有快捷键的唯一入口：Carbon 全局热键与控制台本地按键都经这里分发，
/// 录制期间统一暂停；菜单点击直接调用动作，不再另设 keyEquivalent 造成双触发。
@MainActor
final class ShortcutDispatcher {
    static let shared = ShortcutDispatcher()

    private var handlers: [ShortcutAction: () -> Void] = [:]
    private var consoleMonitor: Any?
    private weak var consoleWindow: NSWindow?
    private(set) var isRecording = false

    private init() {}

    func register(_ action: ShortcutAction, handler: @escaping () -> Void) {
        handlers[action] = handler
    }

    /// 录制快捷键时暂停所有派发，避免边录边触发。
    func setRecording(_ recording: Bool) {
        isRecording = recording
    }

    func perform(_ action: ShortcutAction) {
        guard !isRecording else { return }
        handlers[action]?()
    }

    func startGlobalHotKeys() {
        GlobalHotKeyCenter.shared.start { [weak self] action in
            self?.perform(action)
        }
    }

    /// 控制台窗口内的按键：仅在窗口为 key window 时匹配 .console 动作。
    func installConsoleMonitor(for window: NSWindow) {
        consoleWindow = window
        guard consoleMonitor == nil else { return }
        consoleMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.consoleWindow?.isKeyWindow == true else { return event }
            let modifiers = ShortcutModifiers(eventFlags: event.modifierFlags)
            guard let action = ShortcutAction.allCases.first(where: {
                $0.scope == .console
                    && ShortcutStore.shared.combo(for: $0)?
                        .matches(keyCode: event.keyCode, modifiers: modifiers) == true
            }) else {
                return event
            }
            self.perform(action)
            return nil
        }
    }
}

// MARK: - 修饰键转换

extension ShortcutModifiers {
    init(eventFlags: NSEvent.ModifierFlags) {
        var value: ShortcutModifiers = []
        if eventFlags.contains(.control) { value.insert(.control) }
        if eventFlags.contains(.option) { value.insert(.option) }
        if eventFlags.contains(.shift) { value.insert(.shift) }
        if eventFlags.contains(.command) { value.insert(.command) }
        self = value
    }

    /// Carbon `RegisterEventHotKey` 的修饰键掩码
    var carbonFlags: UInt32 {
        var flags: UInt32 = 0
        if contains(.control) { flags |= UInt32(controlKey) }
        if contains(.option) { flags |= UInt32(optionKey) }
        if contains(.shift) { flags |= UInt32(shiftKey) }
        if contains(.command) { flags |= UInt32(cmdKey) }
        return flags
    }
}

// MARK: - 全局热键

/// Carbon 热键签名 'PNSH'：注册与回调必须使用同一个值。
private let globalHotKeySignature: OSType = 0x504E5348

/// 用 Carbon 全局热键注册「全局」动作：App 未激活时也能响应，且不需要辅助功能权限。
@MainActor
final class GlobalHotKeyCenter {
    static let shared = GlobalHotKeyCenter()

    private var handlerRef: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var failures: Set<ShortcutAction> = []
    private var isStarted = false
    private var onAction: ((ShortcutAction) -> Void)?

    private init() {}

    func start(onAction: @escaping (ShortcutAction) -> Void) {
        guard !isStarted else { return }
        isStarted = true
        self.onAction = onAction
        installHandlerIfNeeded()
        sync()
    }

    /// 按当前配置重新注册；注册失败的动作用于界面提示（可能被系统或其他应用占用）。
    func sync() {
        guard isStarted else { return }
        unregisterAll()
        failures.removeAll()
        for action in ShortcutAction.allCases where action.scope == .global {
            guard let combo = ShortcutStore.shared.combo(for: action) else { continue }
            if !register(combo, for: action) {
                failures.insert(action)
            }
        }
    }

    func registrationFailed(for action: ShortcutAction) -> Bool {
        failures.contains(action)
    }

    fileprivate func perform(_ action: ShortcutAction) {
        onAction?(action)
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(),
                            globalHotKeyHandler,
                            1,
                            &eventType,
                            Unmanaged.passUnretained(self).toOpaque(),
                            &handlerRef)
    }

    private func register(_ combo: ShortcutCombo, for action: ShortcutAction) -> Bool {
        guard let index = ShortcutAction.allCases.firstIndex(of: action) else { return false }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(combo.keyCode),
                                         combo.modifiers.carbonFlags,
                                         EventHotKeyID(signature: globalHotKeySignature,
                                                       id: UInt32(index)),
                                         GetApplicationEventTarget(),
                                         0,
                                         &ref)
        guard status == noErr, let ref else {
            NSLog("PinShell: failed to register shortcut %@ (OSStatus %d)",
                  action.rawValue, status)
            return false
        }
        hotKeyRefs.append(ref)
        return true
    }

    private func unregisterAll() {
        hotKeyRefs.forEach { UnregisterEventHotKey($0) }
        hotKeyRefs.removeAll()
    }
}

/// Carbon 事件回调：只解析动作 id，动作本身切回主线程执行。
private let globalHotKeyHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event,
                                   EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID),
                                   nil,
                                   MemoryLayout<EventHotKeyID>.size,
                                   nil,
                                   &hotKeyID)
    guard status == noErr,
          hotKeyID.signature == globalHotKeySignature,
          hotKeyID.id < UInt32(ShortcutAction.allCases.count) else {
        return OSStatus(eventNotHandledErr)
    }
    let action = ShortcutAction.allCases[Int(hotKeyID.id)]
    let center = Unmanaged<GlobalHotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
    Task { @MainActor in
        center.perform(action)
    }
    return noErr
}
