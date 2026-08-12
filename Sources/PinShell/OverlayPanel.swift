import AppKit

/// 无边框透明悬浮面板：允许在“需要时”成为 key 窗口（WKWebView 偶尔需要 first responder），
/// 但绝不成为 main 窗口，也不抢当前应用的焦点。
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
