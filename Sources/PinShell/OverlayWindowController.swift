import AppKit
import CoreGraphics
import WebKit

/// 悬浮窗口控制器（spec 2.1 / 2.2 / 2.5）：
/// 面板规格、WebView 透明、HTML 加载/重载、穿透切换、frame 持久化。
final class OverlayWindowController: NSObject, NSWindowDelegate {
    private(set) var panel: OverlayPanel!

    private let webView: DraggableWebView
    private let grip = ResizeGripView(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
    private(set) var currentURL: URL?

    private static let defaultSize = NSSize(width: 240, height: 80)
    private static let edgeInset: CGFloat = 24

    override init() {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")   // 本地资源互访
        webView = DraggableWebView(frame: .zero, configuration: config)
        super.init()
        setupPanel()
        setupWebView()
        setupGrip()
        registerFrameObservers()
    }

    // MARK: - 装配

    private func setupPanel() {
        panel = OverlayPanel(
            contentRect: restoreFrame() ?? Self.defaultFrame(),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // .overlay 层级（kCGOverlayWindowLevel=15）：录屏可捕获；禁止 .desktop（多数录屏过滤）
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false                       // 透明窗口的半透明内容合成不可靠（大面积半透明填充被丢弃），阴影一并关闭
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        // 恢复持久化的穿透状态（AppState 为唯一事实来源，UI 控件只读它）
        panel.ignoresMouseEvents = AppState.passthroughEnabled
    }

    private func setupWebView() {
        // 透明设置必须在 init 后、任何 load 之前（见 WKWebView.makeTransparent）
        webView.makeTransparent()
        webView.autoresizingMask = [.width, .height]
        webView.frame = panel.contentView!.bounds
        panel.contentView?.addSubview(webView)
    }

    private func setupGrip() {
        grip.autoresizingMask = [.minXMargin, .maxYMargin]   // 钉住右下角
        grip.frame.origin = NSPoint(
            x: panel.contentView!.bounds.maxX - grip.frame.width,
            y: panel.contentView!.bounds.minY
        )
        grip.isHidden = AppState.passthroughEnabled
        panel.contentView?.addSubview(grip)
    }

    private func registerFrameObservers() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(persistFrame),
                           name: NSWindow.didMoveNotification, object: panel)
        center.addObserver(self, selector: #selector(persistFrame),
                           name: NSWindow.didResizeNotification, object: panel)
    }

    // MARK: - 对外接口

    func showWindow() {
        panel.orderFront(nil)   // 不用 orderFrontRegardless：会破坏 nonactivating 语义、抢焦点
    }

    func loadHTML(_ url: URL) {
        let resolved = url.standardizedFileURL
        guard resolved.isRegularFile else { return }
        currentURL = resolved
        webView.loadLocalHTMLFile(resolved)
        AppState.lastHTMLURL = resolved
    }

    func reloadHTML() {
        if let url = currentURL { loadHTML(url) }
    }

    func setPassthrough(_ enabled: Bool) {
        panel.ignoresMouseEvents = enabled   // 窗口级开关：穿透 + 禁拖动一次生效
        grip.isHidden = enabled
        AppState.passthroughEnabled = enabled
        // 通知只作变化信号，观察者一律从 AppState 读状态（单一事实来源）
        NotificationCenter.default.post(name: .pinshellPassthroughChanged, object: nil)
    }

    @discardableResult
    func togglePassthrough() -> Bool {
        let next = !AppState.passthroughEnabled
        setPassthrough(next)
        return next
    }

    func resetToDefaultFrame() {
        panel.setFrame(Self.defaultFrame(), display: true)
    }

    /// 应用模板推荐尺寸：保持右下角锚定（窗口向左上扩展）
    func applyTemplateSize(_ size: NSSize) {
        let f = panel.frame
        panel.setFrame(NSRect(x: f.maxX - size.width, y: f.minY,
                              width: size.width, height: size.height),
                       display: true)
    }


    // MARK: - 状态持久化

    private var framePersistWork: DispatchWorkItem?

    /// 拖动/缩放期间 didMove/didResize 以显示刷新率触发：防抖后一次性落盘
    @objc private func persistFrame() {
        framePersistWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            AppState.windowFrame = self.panel.frame
        }
        framePersistWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// 恢复上次 frame；若已不在任何可见屏幕（显示器变更），回落默认位置
    private func restoreFrame() -> NSRect? {
        guard let frame = AppState.windowFrame else { return nil }
        let visible = NSScreen.screens.map(\.visibleFrame)
        guard visible.contains(where: { $0.intersects(frame) }) else { return nil }
        return frame
    }

    /// 默认位置：主屏右下角，24pt 边距
    static func defaultFrame() -> NSRect {
        guard let vf = NSScreen.main?.visibleFrame else {
            return NSRect(origin: .zero, size: defaultSize)
        }
        return NSRect(x: vf.maxX - defaultSize.width - edgeInset,
                      y: vf.minY + edgeInset,
                      width: defaultSize.width,
                      height: defaultSize.height)
    }
}

extension Notification.Name {
    /// 穿透开关变化信号（观察者从 AppState 读状态）——菜单项与模板库开关同步
    static let pinshellPassthroughChanged = Notification.Name("PinShell.passthroughChanged")
}
