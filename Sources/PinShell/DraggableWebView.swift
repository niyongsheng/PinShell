import AppKit
import WebKit

/// 默认把点击交给 HTML；按住 ⌘ 拖动窗口（performDrag 交由 Window Server 处理）。
/// 穿透开启时 ignoresMouseEvents = true，事件根本不会到达这里 —— 拖拽与穿透天然互斥。
final class DraggableWebView: WKWebView {
    /// 页面加载完成/失败回调（OverlayWindowController 转发给 CLI listen / show --wait）
    weak var owner: OverlayWindowController?

    override init(frame: NSRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        navigationDelegate = self   // didFinish 时同步穿透状态
        // 穿透 DOM 状态归本视图管理：观察变化信号，从 AppState 读状态应用（单一事实来源）
        NotificationCenter.default.addObserver(self, selector: #selector(passthroughChanged),
                                               name: .pinshellPassthroughChanged, object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            window?.performDrag(with: event)
            return
        }
        // nonactivating panel 默认可能吞掉首次点击；点击进入页面时主动成为 key，
        // 让 HTML 表单/输入框能接收键盘事件（不会激活整个 App）。
        window?.makeKey()
        super.mouseDown(with: event)
    }

    /// 非激活窗口的第一次点击也交给 WebKit 处理。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var mouseDownCanMoveWindow: Bool { false }

    // MARK: - 穿透状态注入（透明度全权交给 HTML）

    /// 穿透时给 <html> 加 passthrough class，并注入默认淡化样式；
    /// 模板可用 --ps-passthrough-opacity 覆盖淡出程度（token 默认值见 design-tokens.css）。
    /// 默认回退（自定义 HTML 未引用 token 时）：html 整体按该变量淡化。
    private static let defaultPassthroughCSS = "html.passthrough{opacity:var(--ps-passthrough-opacity,0.65)}"

    private static let passthroughOnJS = """
    (function(){
      if (!document.getElementById('ps-passthrough-default')) {
        var s = document.createElement('style');
        s.id = 'ps-passthrough-default';
        s.textContent = '\(defaultPassthroughCSS)';
        document.documentElement.appendChild(s);
      }
      document.documentElement.classList.add('passthrough');
    })();
    """

    private static let passthroughOffJS = """
    document.documentElement.classList.remove('passthrough');
    """

    @objc private func passthroughChanged(_ notification: Notification) {
        applyPassthrough(AppState.passthroughEnabled)
    }

    func applyPassthrough(_ enabled: Bool) {
        evaluateJavaScript(enabled ? Self.passthroughOnJS : Self.passthroughOffJS,
                           completionHandler: nil)
    }

}

extension DraggableWebView: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // 重载/换文件后同步穿透状态。关闭态无需注入：新页面初始本无 passthrough class
        if AppState.passthroughEnabled {
            applyPassthrough(true)
        }
        owner?.handlePageDidLoad()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        owner?.handlePageLoadFailure(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        owner?.handlePageLoadFailure(error)
    }
}
