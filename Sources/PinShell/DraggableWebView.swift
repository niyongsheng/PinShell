import AppKit
import WebKit

/// 编辑模式下，所有鼠标按下都用于拖动窗口（performDrag 交由 Window Server 处理）。
/// 穿透开启时 ignoresMouseEvents = true，事件根本不会到达这里 —— 拖拽与穿透天然互斥。
/// （WKWebView 自吞 mouseDown，mouseDownCanMoveWindow 不可靠，故用此显式方案。）
final class DraggableWebView: WKWebView {
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
        window?.performDrag(with: event)
    }

    // MARK: - 穿透状态注入（透明度全权交给 HTML）

    /// 穿透时给 <html> 加 passthrough class，并把滑块透明度写入 CSS 变量
    /// --ps-passthrough-opacity；模板用 var() 引用它（token 默认值见 design-tokens.css）。
    /// 默认回退（自定义 HTML 未引用 token 时）：html 整体按该变量淡化。
    private static let defaultPassthroughCSS = "html.passthrough{opacity:var(--ps-passthrough-opacity,0.65)}"

    private static func setOpacityVarJS(_ opacity: Double) -> String {
        "document.documentElement.style.setProperty('--ps-passthrough-opacity', \(opacity));"
    }

    private static func passthroughOnJS(_ opacity: Double) -> String {
        """
        (function(){
          \(setOpacityVarJS(opacity))
          if (!document.getElementById('ps-passthrough-default')) {
            var s = document.createElement('style');
            s.id = 'ps-passthrough-default';
            s.textContent = '\(defaultPassthroughCSS)';
            document.documentElement.appendChild(s);
          }
          document.documentElement.classList.add('passthrough');
        })();
        """
    }

    private static let passthroughOffJS = """
    document.documentElement.classList.remove('passthrough');
    """

    @objc private func passthroughChanged(_ notification: Notification) {
        applyPassthrough(AppState.passthroughEnabled)
    }

    func applyPassthrough(_ enabled: Bool) {
        let opacity = AppState.passthroughOpacity
        evaluateJavaScript(enabled ? Self.passthroughOnJS(opacity) : Self.passthroughOffJS,
                           completionHandler: nil)
    }

    // MARK: - 滑块：同帧合并 + 值相同跳过（拖动 ~60Hz 时避免逐 tick 跨进程 IPC）

    private var pendingOpacity: Double?
    private var flushScheduled = false

    func setPassthroughOpacity(_ opacity: Double) {
        pendingOpacity = opacity
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.flushScheduled = false
            self?.flushPendingOpacity()
        }
    }

    private func flushPendingOpacity() {
        guard let opacity = pendingOpacity else { return }
        pendingOpacity = nil
        evaluateJavaScript(Self.setOpacityVarJS(opacity), completionHandler: nil)
    }
}

extension DraggableWebView: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // 重载/换文件后同步穿透状态。关闭态无需注入：新页面初始本无 passthrough class
        guard AppState.passthroughEnabled else { return }
        applyPassthrough(true)
    }
}
