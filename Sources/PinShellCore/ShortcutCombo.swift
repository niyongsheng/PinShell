import Foundation

/// 快捷键修饰键：与 AppKit 解耦，便于持久化和单元测试。
public struct ShortcutModifiers: OptionSet, Hashable, Codable, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static let control = ShortcutModifiers(rawValue: 1 << 0)
    public static let option = ShortcutModifiers(rawValue: 1 << 1)
    public static let shift = ShortcutModifiers(rawValue: 1 << 2)
    public static let command = ShortcutModifiers(rawValue: 1 << 3)

    /// 录制快捷键时至少需要按住其中一个，避免单键全局热键抢占普通输入。
    public static let required: ShortcutModifiers = [.command, .option, .control]
}

/// 一个快捷键组合：物理键位 + 修饰键 + 归一化后的主键字符。
///
/// 用物理 `keyCode` 而不是字符做匹配：同一组合在不同键盘布局下的字符可能不同，
/// 但用户按下的键位是稳定的。`key` 仅用于界面展示。
public struct ShortcutCombo: Hashable, Codable, Sendable {
    public let keyCode: UInt16
    public let modifiers: ShortcutModifiers
    /// 归一化的主键字符：字母小写，Shift 产生的符号还原为基键（如 "!" → "1"）；
    /// 特殊键保留 `charactersIgnoringModifiers` 的原始值（如 "\r"）。
    public let key: String

    public init(keyCode: UInt16, modifiers: ShortcutModifiers, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    /// 从 `NSEvent` 的 keyCode / 修饰键 / charactersIgnoringModifiers 生成。
    public init?(keyCode: UInt16, modifiers: ShortcutModifiers, characters: String) {
        guard let first = characters.first else { return nil }
        let normalized: String
        if let base = Self.shiftedBaseCharacters[first] {
            normalized = String(base)
        } else {
            normalized = String(first).lowercased()
        }
        guard !normalized.isEmpty else { return nil }
        self.init(keyCode: keyCode, modifiers: modifiers, key: normalized)
    }

    /// 至少包含一个 ⌘ / ⌥ / ⌃，避免把普通按键变成快捷键。
    public var isValid: Bool {
        !key.isEmpty && !modifiers.intersection(.required).isEmpty
    }

    /// 菜单与界面展示：修饰键按 ⌃⌥⇧⌘ 顺序 + 主键。
    public var displayString: String {
        var symbols = ""
        if modifiers.contains(.control) { symbols += "⌃" }
        if modifiers.contains(.option) { symbols += "⌥" }
        if modifiers.contains(.shift) { symbols += "⇧" }
        if modifiers.contains(.command) { symbols += "⌘" }
        return symbols + displayKey
    }

    /// 主键的展示文本：特殊键用符号，字母大写，其余原样。
    public var displayKey: String {
        if let special = Self.specialKeyNames[keyCode] { return special }
        return key.uppercased()
    }

    /// 只比较物理键位与修饰键，忽略布局相关的字符差异。
    public func matches(keyCode: UInt16, modifiers: ShortcutModifiers) -> Bool {
        self.keyCode == keyCode && self.modifiers == modifiers
    }

    public func isEquivalent(to other: ShortcutCombo) -> Bool {
        matches(keyCode: other.keyCode, modifiers: other.modifiers)
    }

    // MARK: - 展示映射

    /// 标准 ANSI 键位的固定展示名（kVK_Return…kVK_F12）。
    private static let specialKeyNames: [UInt16: String] = [
        36: "↩",    // Return
        48: "⇥",    // Tab
        49: "Space",
        51: "⌫",    // Delete
        53: "⎋",    // Escape
        76: "⌤",    // Keypad Enter
        115: "↖",   // Home
        116: "⇞",   // Page Up
        117: "⌦",   // Forward Delete
        119: "↘",   // End
        121: "⇟",   // Page Down
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    /// Shift + 数字/符号键的字符还原（US 布局）：展示与菜单统一用基键 + ⇧。
    private static let shiftedBaseCharacters: [Character: Character] = [
        "!": "1", "@": "2", "#": "3", "$": "4", "%": "5",
        "^": "6", "&": "7", "*": "8", "(": "9", ")": "0",
        "_": "-", "+": "=", "{": "[", "}": "]", "|": "\\",
        ":": ";", "\"": "'", "<": ",", ">": ".", "?": "/", "~": "`",
    ]
}
