import AppKit
import WebKit

/// 编辑模式下，所有鼠标按下都用于拖动窗口（performDrag 交由 Window Server 处理）。
/// 穿透开启时 ignoresMouseEvents = true，事件根本不会到达这里 —— 拖拽与穿透天然互斥。
/// （WKWebView 自吞 mouseDown，mouseDownCanMoveWindow 不可靠，故用此显式方案。）
final class DraggableWebView: WKWebView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
