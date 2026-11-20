import AppKit
import CoreGraphics
import WebKit
import PinShellCore

/// 悬浮窗口控制器：面板规格、WebView 透明、HTML 加载/重载、
/// 声明式窗口属性（meta/CLI/JS 桥）、穿透切换、frame 持久化、文件热重载。
final class OverlayWindowController: NSObject, NSWindowDelegate {
    private(set) var panel: OverlayPanel!

    private let webView: DraggableWebView
    private let bridge: JSBridge
    private let userContentController: WKUserContentController
    private let fetchSession: URLSession
    private let grip = ResizeGripView(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
    private(set) var currentURL: URL?

    /// 控制通道事件出口（ControlHost 订阅后广播给 listen 客户端）
    var onControlEvent: ((ControlEvent) -> Void)?
    /// 页面加载完成 / 失败回调（show --wait）
    var onPageLoaded: (() -> Void)?
    var onPageLoadFailed: ((Error) -> Void)?

    /// 最近一次 show 的 CLI 显式参数；reload 时继续生效
    private var sessionSpecOverrides: WindowSpec?
    private var isApplyingProgrammaticFrame = false
    private var currentRadius: Double = 0
    private var fileWatcher: FileWatcher?
    private var watchEnabled = false

    override init() {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")   // 本地资源互访
        // HTML 主导声音：本地模板视为可信内容，允许自动播放
        config.mediaTypesRequiringUserActionForPlayback = []

        let controller = WKUserContentController()
        let bridge = JSBridge()
        controller.add(bridge, name: "pinshell")
        controller.addUserScript(WKUserScript(source: JSBridge.injectionScript,
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true))
        config.userContentController = controller

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = 15
        sessionConfiguration.timeoutIntervalForResource = 20
        self.fetchSession = URLSession(configuration: sessionConfiguration)
        self.userContentController = controller
        self.bridge = bridge
        self.webView = DraggableWebView(frame: .zero, configuration: config)

        super.init()

        bridge.controller = self
        webView.owner = self

        setupPanel()
        setupWebView()
        setupGrip()
        registerFrameObservers()
    }

    deinit {
        fileWatcher?.stop()
        userContentController.removeScriptMessageHandler(forName: "pinshell")
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
        panel.contentView?.addSubview(grip)
        syncPassthroughUI()
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
        notifyStatusChanged()
    }

    func hideWindow() {
        panel.orderOut(nil)
        notifyStatusChanged()
    }

    /// 加载 HTML：
    /// - 解析 HTML meta 得到声明式窗口属性；
    /// - specOverride 为 CLI 显式参数（会话级，reload 继续生效；传 nil 清空）；
    /// - 复位上一个模板遗留的 opacity/radius，避免跨文件泄漏。
    func loadHTML(_ url: URL, specOverride: WindowSpec? = nil) {
        let resolved = url.standardizedFileURL
        guard resolved.isRegularFile else { return }
        currentURL = resolved
        sessionSpecOverrides = specOverride
        resetTransientWindowStyle()
        applyDeclaredSpec(for: resolved)
        webView.loadLocalHTMLFile(resolved)
        AppState.lastHTMLURL = resolved
        showWindow()
        updateFileWatcher()
        notifyStatusChanged()
    }

    /// 重新应用声明值并重载当前文件；不清除 session overrides / watch 状态。
    func reloadHTML() {
        guard let url = currentURL else { return }
        resetTransientWindowStyle()
        applyDeclaredSpec(for: url)
        webView.loadLocalHTMLFile(url)
    }

    /// 卸载当前页面并清空当前文件（当前模板被删除时使用）。
    func clearHTML() {
        currentURL = nil
        sessionSpecOverrides = nil
        resetTransientWindowStyle()
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
        updateFileWatcher()
        hideWindow()
        notifyStatusChanged()
    }

    // MARK: - 声明式窗口属性

    /// HTML meta 的窗口属性（不含 CLI override）。
    private func applyDeclaredSpec(for url: URL) {
        // 与模板库同一套有效元数据：HTML meta > 同名内置模板 > 默认尺寸
        let metadata = TemplateStore.effectiveMetadata(for: url)
        applyWindowSpec(metadata.windowSpec.merging(overrides: sessionSpecOverrides))
    }

    /// 统一入口：size/position/passthrough/opacity/radius。
    /// - HTML meta、模板库 Apply、JS bridge、CLI 都走这里。
    func applyWindowSpec(_ spec: WindowSpec) {
        if spec.size != nil || spec.position != nil {
            applyDeclaredFrame(size: spec.size, position: spec.position)
        }
        if let enabled = spec.passthrough {
            setPassthrough(enabled)
        }
        if let opacity = spec.opacity {
            setWindowOpacity(opacity)
        }
        if let radius = spec.radius {
            setWindowRadius(radius)
        }
        notifyStatusChanged()
    }

    /// CLI `set`：把局部参数并入会话 override 后重新应用。
    func applyControlSpec(_ partial: WindowSpec) {
        sessionSpecOverrides = (sessionSpecOverrides ?? .empty).merging(overrides: partial)
        if let url = currentURL {
            applyDeclaredSpec(for: url)
        } else {
            applyWindowSpec(partial)
        }
    }

    private func applyDeclaredFrame(size: WindowSize?, position: WindowPosition?) {
        guard let visible = (panel.screen ?? NSScreen.main)?.visibleFrame else { return }
        let current = panel.frame
        let resolved = WindowGeometry.resolve(
            size: size,
            position: position,
            current: WindowFrame(x: current.origin.x,
                                 y: current.origin.y,
                                 width: current.size.width,
                                 height: current.size.height),
            screen: WindowFrame(x: visible.origin.x,
                                y: visible.origin.y,
                                width: visible.size.width,
                                height: visible.size.height)
        )
        let target = NSRect(x: CGFloat(resolved.x), y: CGFloat(resolved.y),
                            width: CGFloat(resolved.width), height: CGFloat(resolved.height))
        guard !target.equalTo(panel.frame) else { return }
        applyProgrammaticFrame(target)
    }

    private func applyProgrammaticFrame(_ frame: NSRect) {
        // 程序化 frame 不应覆盖用户手动拖动留下的持久值
        framePersistWork?.cancel()
        framePersistWork = nil
        isApplyingProgrammaticFrame = true
        panel.setFrame(frame, display: true)
        notifyStatusChanged()
        DispatchQueue.main.async { [weak self] in
            self?.isApplyingProgrammaticFrame = false
        }
    }

    private func resetTransientWindowStyle() {
        setWindowRadius(0)
        setWindowOpacity(1)
    }

    /// 整窗透明度（0..1），与穿透淡化 CSS 变量相互独立。
    func setWindowOpacity(_ value: Double) {
        guard value.isFinite else { return }
        panel.alphaValue = min(max(CGFloat(value), 0), 1)
        notifyStatusChanged()
    }

    /// 窗口级圆角（px）：仅裁剪 contentView，HTML 自身 CSS 圆角仍是首选。
    func setWindowRadius(_ value: Double) {
        guard value.isFinite, value >= 0 else { return }
        currentRadius = value
        guard let contentView = panel.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = CGFloat(value)
        contentView.layer?.masksToBounds = value > 0
        notifyStatusChanged()
    }

    func setWindowSize(width: Double, height: Double) {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return }
        applyWindowSpec(WindowSpec(size: WindowSize(width: width, height: height)))
    }

    func setWindowPosition(_ position: WindowPosition) {
        applyWindowSpec(WindowSpec(position: position))
    }

    // MARK: - 页面 → 原生事件

    func broadcast(_ event: ControlEvent) {
        onControlEvent?(event)
    }

    func handlePageDidLoad() {
        if let url = currentURL {
            broadcast(.loaded(file: url.path, url: url.absoluteString))
        }
        onPageLoaded?()
        notifyStatusChanged()
    }

    func handlePageLoadFailure(_ error: Error) {
        let nsError = error as NSError
        // 快速 reload 会取消旧导航，不属于用户可见错误
        guard !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) else { return }
        NSLog("PinShell load failed: %@", nsError.localizedDescription)
        broadcast(.error(nsError.localizedDescription))
        onPageLoadFailed?(error)
    }

    /// CLI `emit`：派发 window CustomEvent，HTML 用 pinshell.on 订阅。
    func dispatchEvent(name: String, data: JSONValue) {
        let payload: [String: Any] = ["name": name, "data": data.anyValue]
        guard JSONSerialization.isValidJSONObject(payload),
              let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: jsonData, encoding: .utf8) else { return }
        webView.evaluateJavaScript(
            "window.dispatchEvent(new CustomEvent('pinshell:event',{detail:\(json)}));",
            completionHandler: nil
        )
    }

    // MARK: - 页面 fetch 代理

    /// HTML 里的 `pinshell.fetch(url, options)`：由原生 URLSession 代发请求，
    /// 可携带 Referer 等浏览器受限的请求头（B 站 API 需要 Referer）。
    func performFetch(id: String, url: URL, headers: [String: String]) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.httpMethod = "GET"
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
                + "(KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        fetchSession.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.resolveFetch(id: id, ok: false, body: "",
                                      error: error.localizedDescription)
                    return
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard (200..<300).contains(status), let data, data.count <= 2 * 1024 * 1024 else {
                    self.resolveFetch(id: id, ok: false, body: "",
                                      error: "HTTP \(status)")
                    return
                }
                let body = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1)
                    ?? ""
                self.resolveFetch(id: id, ok: true, body: body, error: "")
            }
        }.resume()
    }

    func resolveFetch(id: String, ok: Bool, body: String, error: String) {
        let script = "window.__pinshellFetchResult(\(jsString(id)), \(ok ? "true" : "false"), "
            + "\(jsString(body)), \(jsString(error)));"
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private func jsString(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let string = String(data: data, encoding: .utf8) else { return "\"\"" }
        return string
    }

    /// CLI `eval`：返回可 JSON 化的 JS 结果。
    func evaluate(script: String, completion: @escaping (Result<JSONValue, EvaluationError>) -> Void) {
        webView.evaluateJavaScript(script) { result, error in
            if let error {
                completion(.failure(EvaluationError(message: error.localizedDescription)))
            } else {
                completion(.success(JSONValue(any: result ?? NSNull())))
            }
        }
    }

    // MARK: - 热重载

    func setWatching(_ enabled: Bool) {
        watchEnabled = enabled
        updateFileWatcher()
        notifyStatusChanged()
    }

    private func updateFileWatcher() {
        fileWatcher?.stop()
        fileWatcher = nil
        guard watchEnabled, let url = currentURL else { return }
        let watcher = FileWatcher(url: url) { [weak self] in
            self?.reloadHTML()
        }
        watcher.start()
        fileWatcher = watcher
    }

    // MARK: - 穿透

    func setPassthrough(_ enabled: Bool) {
        AppState.passthroughEnabled = enabled
        // 通知只作变化信号，观察者（菜单项/模板库开关/WebView）从 AppState 读状态
        NotificationCenter.default.post(name: .pinshellPassthroughChanged, object: nil)
        syncPassthroughUI()
        notifyStatusChanged()
    }

    /// 从 AppState 派生全部穿透 UI（窗口/拖拽手柄），init 与切换共用一条路径
    private func syncPassthroughUI() {
        let enabled = AppState.passthroughEnabled
        panel.ignoresMouseEvents = enabled   // 窗口级开关：穿透 + 禁拖动一次生效
        grip.isHidden = enabled
    }

    @discardableResult
    func togglePassthrough() -> Bool {
        let next = !AppState.passthroughEnabled
        setPassthrough(next)
        return next
    }

    /// 菜单滑块：实时注入 CSS 变量（穿透开关状态不受影响），落盘沿用拖动防抖惯例
    private var opacityPersistWork: DispatchWorkItem?

    func setPassthroughOpacity(_ opacity: Double) {
        webView.setPassthroughOpacity(opacity)
        opacityPersistWork?.cancel()
        let work = DispatchWorkItem { AppState.passthroughOpacity = opacity }
        opacityPersistWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// 预设四角：保持当前尺寸，贴到所在屏幕可见区域角落（默认 24pt 边距）
    func moveToCorner(_ corner: WindowAnchor) {
        guard let visible = (panel.screen ?? NSScreen.main)?.visibleFrame else { return }
        let size = panel.frame.size
        let inset = CGFloat(WindowGeometry.defaultInset)
        let x = corner.isLeft
            ? visible.minX + inset
            : max(visible.minX + inset, visible.maxX - size.width - inset)
        let y = corner.isTop
            ? max(visible.minY + inset, visible.maxY - size.height - inset)
            : visible.minY + inset
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        notifyStatusChanged()
    }

    // MARK: - 状态

    /// 状态变化广播：控制台据此刷新状态胶囊与「窗口」页
    private func notifyStatusChanged() {
        NotificationCenter.default.post(name: .pinshellStatusChanged, object: nil)
    }

    func status() -> JSONValue {
        let frame = panel.frame
        return .object([
            "file": currentURL.map { .string($0.path) } ?? .null,
            "visible": .bool(panel.isVisible),
            "watching": .bool(watchEnabled && fileWatcher != nil),
            "passthrough": .bool(AppState.passthroughEnabled),
            "opacity": .number(Double(panel.alphaValue)),
            "radius": .number(currentRadius),
            "frame": .object([
                "x": .number(Double(frame.origin.x)),
                "y": .number(Double(frame.origin.y)),
                "width": .number(Double(frame.size.width)),
                "height": .number(Double(frame.size.height))
            ])
        ])
    }

    // MARK: - 状态持久化

    private var framePersistWork: DispatchWorkItem?

    /// 拖动/缩放期间 didMove/didResize 以显示刷新率触发：防抖后一次性落盘
    @objc private func persistFrame() {
        guard !isApplyingProgrammaticFrame else { return }
        framePersistWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            AppState.windowFrame = self.panel.frame
            self.notifyStatusChanged()
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
        let size = WindowSize.fallback
        guard let vf = NSScreen.main?.visibleFrame else {
            return NSRect(origin: .zero,
                          size: NSSize(width: CGFloat(size.width),
                                       height: CGFloat(size.height)))
        }
        let inset = CGFloat(WindowGeometry.defaultInset)
        return NSRect(x: vf.maxX - CGFloat(size.width) - inset,
                      y: vf.minY + inset,
                      width: CGFloat(size.width),
                      height: CGFloat(size.height))
    }
}

extension Notification.Name {
    /// 穿透开关变化信号（观察者从 AppState 读状态）——菜单项、控制台与 WebView 同步
    static let pinshellPassthroughChanged = Notification.Name("PinShell.passthroughChanged")
    /// 控制台状态刷新（frame / 文件 / watch / opacity / radius 等变化）
    static let pinshellStatusChanged = Notification.Name("PinShell.statusChanged")
}

/// evaluateJavaScript 失败的轻量错误包装。
struct EvaluationError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
