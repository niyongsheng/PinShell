import AppKit
import CoreGraphics
import WebKit
import PinShellCore

/// 菜单栏弹出的锚点快照：状态栏按钮在屏幕坐标中的 frame + 所在屏幕的可见区域。
struct StatusItemAnchor {
    /// nil 表示拿不到按钮位置，几何计算回落到屏幕顶部中央。
    let iconFrame: WindowFrame?
    let visibleFrame: WindowFrame
}

/// 悬浮窗口控制器：面板规格、WebView 透明、HTML 加载/重载、
/// 声明式窗口属性（meta/CLI/JS 桥）、穿透切换、frame 持久化、文件热重载。
final class OverlayWindowController: NSObject, NSWindowDelegate {
    private(set) var panel: OverlayPanel!

    /// 桌面悬浮层与菜单栏弹出面板的窗口层级。
    private static let overlayLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
    private static let menuBarLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)))

    private let webView: DraggableWebView
    private let bridge: JSBridge
    private let userContentController: WKUserContentController
    private let fetchSession: URLSession
    private let grip = ResizeGripView(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
    private(set) var currentURL: URL?
    /// 一次面板展示的生命周期标识；所有事件都带上它，重载保持、新 show 更换。
    private(set) var sessionID = UUID().uuidString
    /// 页面通过 pinshell.setState / patchState 维护的共享状态（原生侧权威副本）。
    private(set) var panelState: JSONValue = .object([:])
    private(set) var stateRevision = 0

    /// 当前展示方式（持久化在 AppState，单一事实来源）。
    var displayMode: DisplayMode { AppState.displayMode }
    /// StatusItemController 注入：返回状态栏按钮位置与所在屏幕的可见区域。
    var statusItemAnchorProvider: (() -> StatusItemAnchor?)?
    /// 菜单栏弹出期间的收起监听（只在展示期间安装）。
    private var globalMouseMonitor: Any?
    private var localKeyMonitor: Any?
    private var workspaceObservers: [NSObjectProtocol] = []
    /// 展示时刻：忽略菜单收起瞬间的 App 激活切换，避免刚弹出就被误收起。
    private var popoverPresentedAt = Date.distantPast

    /// 穿透只在桌面模式生效；菜单栏弹出必须始终可点击。
    var effectivePassthroughEnabled: Bool {
        displayMode == .desktop && AppState.passthroughEnabled
    }

    /// 菜单栏弹出模式禁用 ⌘ 拖窗（位置始终锚定图标）。
    var allowsCommandDrag: Bool { displayMode == .desktop }

    /// 内置占位页：首启兜底，不算“用户已选模板”。
    static var placeholderURL: URL? {
        Bundle.main.url(forResource: "Placeholder", withExtension: "html")
    }

    static func isPlaceholder(_ url: URL) -> Bool {
        url.standardizedFileURL == placeholderURL?.standardizedFileURL
    }

    /// 是否有真实模板内容（内置 Placeholder 不算），用于决定左键是否直接开菜单。
    var hasUserContent: Bool {
        currentURL.map { !Self.isPlaceholder($0) } ?? false
    }

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
        applyDisplayModeConfiguration()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    deinit {
        fileWatcher?.stop()
        removePopoverDismissMonitors()
        NotificationCenter.default.removeObserver(self)
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
        // 菜单栏弹出时提升到 .statusBar（25），保证盖住普通窗口与全屏辅助层。
        panel.level = displayMode == .desktop ? Self.overlayLevel : Self.menuBarLevel
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

    var isWindowVisible: Bool { panel.isVisible }

    func showWindow() {
        if displayMode == .menuBar {
            presentMenuBarPopover()
            return
        }
        panel.orderFront(nil)   // 不用 orderFrontRegardless：会破坏 nonactivating 语义、抢焦点
        notifyStatusChanged()
    }

    func hideWindow() {
        removePopoverDismissMonitors()
        panel.orderOut(nil)
        notifyStatusChanged()
    }

    func toggleVisibility() {
        if panel.isVisible {
            hideWindow()
        } else {
            showWindow()
        }
    }

    /// 菜单栏弹出期间的主动收起（打开控制台、弹窗前调用）；其他模式/已隐藏时无操作。
    func dismissMenuBarPopover() {
        guard displayMode == .menuBar, panel.isVisible else { return }
        hideWindow()
    }

    // MARK: - 显示方式（桌面悬浮 / 菜单栏弹出）

    func setDisplayMode(_ mode: DisplayMode) {
        guard mode != displayMode else { return }
        let wasVisible = panel.isVisible

        if displayMode == .desktop, wasVisible {
            // 离开桌面模式前落盘最后的桌面位置，之后弹出定位不再污染它。
            framePersistWork?.cancel()
            framePersistWork = nil
            AppState.windowFrame = panel.frame
        }
        removePopoverDismissMonitors()
        if wasVisible { panel.orderOut(nil) }   // 避免跨屏跳变的中间态

        AppState.displayMode = mode
        applyDisplayModeConfiguration()

        if mode == .desktop {
            restoreDesktopFrame()
            if wasVisible { panel.orderFront(nil) }
        } else if wasVisible {
            // 从菜单触发时避开菜单收起，等下一轮 runloop 再贴到图标下方。
            DispatchQueue.main.async { [weak self] in
                self?.presentMenuBarPopover()
            }
        }
        notifyStatusChanged()
    }

    private func applyDisplayModeConfiguration() {
        panel.level = displayMode == .desktop ? Self.overlayLevel : Self.menuBarLevel
        syncPassthroughUI()
        // 页面尚未加载时无需注入；didFinish 会按有效穿透状态补一次。
        if webView.url != nil {
            webView.applyPassthrough(effectivePassthroughEnabled)
        }
    }

    /// 回到桌面模式：优先恢复用户上次的桌面位置；尺寸始终沿用当前模板。
    /// 不能整帧恢复旧记录：历史 frame 可能来自别的模板/别的会话，
    /// 切换显示方式时会把当前模板撑大或压小（例如 240×80 的徽章变成 320×520）。
    private func restoreDesktopFrame() {
        if let saved = restoreFrame(),
           let visible = NSScreen.screens
               .first(where: { $0.visibleFrame.intersects(saved) })?.visibleFrame {
            // 尺寸变化后把左上角夹回屏幕内，避免窗口跑出可视区。
            let frame = WindowGeometry.resolve(
                size: WindowSize(width: Double(panel.frame.width),
                                 height: Double(panel.frame.height)),
                position: .absolute(x: Double(saved.minX), y: Double(saved.minY)),
                current: WindowFrame(panel.frame),
                screen: WindowFrame(visible))
            applyProgrammaticFrame(frame.nsRect)
            return
        }
        applyProgrammaticFrame(Self.defaultFrame())
        if let url = currentURL {
            applyDeclaredSpec(for: url)
        }
    }

    private func presentMenuBarPopover() {
        guard displayMode == .menuBar, currentURL != nil else { return }
        popoverPresentedAt = Date()
        anchorMenuBarPopover(requestedSize: nil)
        panel.orderFront(nil)
        installPopoverDismissMonitors()
        notifyStatusChanged()
    }

    /// 顶部居中贴到状态栏图标下方；requestedSize 为 nil 时沿用当前窗口尺寸。
    private func anchorMenuBarPopover(requestedSize: WindowSize?) {
        guard displayMode == .menuBar else { return }
        guard let anchor = statusItemAnchorProvider?() ?? fallbackAnchor() else { return }
        let current = panel.frame
        let size = requestedSize ?? WindowSize(width: Double(current.width),
                                               height: Double(current.height))
        let resolved = MenuBarPopoverGeometry.resolve(
            size: size,
            iconFrame: anchor.iconFrame,
            visibleFrame: anchor.visibleFrame
        )
        let target = resolved.nsRect
        guard !target.equalTo(panel.frame) else { return }
        applyProgrammaticFrame(target)
    }

    private func fallbackAnchor() -> StatusItemAnchor? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
        return StatusItemAnchor(iconFrame: nil, visibleFrame: WindowFrame(screen.visibleFrame))
    }

    @objc private func screenParametersChanged() {
        guard displayMode == .menuBar, panel.isVisible else { return }
        anchorMenuBarPopover(requestedSize: nil)
    }

    // MARK: - 菜单栏弹窗收起监听

    private func installPopoverDismissMonitors() {
        guard displayMode == .menuBar else { return }
        removePopoverDismissMonitors()

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.dismissMenuBarPopover() }
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow, event.keyCode == 53 else { return event }
            self.dismissMenuBarPopover()
            return nil
        }

        // 切 Space / 切到别的 App 时收起，避免面板挂在所有空间上。
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.dismissMenuBarPopover()
        })
        workspaceObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            // 菜单收起会把焦点还给之前的 App；展示后短暂窗口内的激活切换不算用户切走。
            guard Date().timeIntervalSince(self.popoverPresentedAt) > 0.5 else { return }
            // 只对切到其它 App 收起；本 App 打开菜单/控制台时不要误伤（控制台会显式收起）。
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
                return
            }
            self.dismissMenuBarPopover()
        })
    }

    private func removePopoverDismissMonitors() {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            workspaceCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
    }

    /// 加载 HTML：
    /// - 解析 HTML meta 得到声明式窗口属性；
    /// - specOverride 为 CLI 显式参数（会话级，reload 继续生效；传 nil 清空）；
    /// - present 为 false 时只加载不展示（菜单栏模式启动恢复上次模板）；
    /// - 复位上一个模板遗留的 opacity/radius，避免跨文件泄漏。
    func loadHTML(_ url: URL, specOverride: WindowSpec? = nil, present: Bool = true) {
        let resolved = url.standardizedFileURL
        guard resolved.isRegularFile else { return }
        currentURL = resolved
        sessionSpecOverrides = specOverride
        beginSession()
        resetTransientWindowStyle()
        let metadata = applyDeclaredSpec(for: resolved)
        installBridgeScript(templateLanguage: metadata.resolvedLanguage)
        webView.loadLocalHTMLFile(resolved)
        // 占位页只是首启兜底，不记为用户选择。
        if !Self.isPlaceholder(resolved) {
            AppState.lastHTMLURL = resolved
        }
        if present { showWindow() }
        updateFileWatcher()
        notifyStatusChanged()
    }

    private func beginSession() {
        let previous = sessionID
        sessionID = UUID().uuidString
        panelState = .object([:])
        stateRevision = 0
        broadcast(.sessionStarted(previous: previous))
    }

    /// 重新应用声明值并重载当前文件；不清除 session overrides / watch 状态。
    func reloadHTML() {
        guard let url = currentURL else { return }
        resetTransientWindowStyle()
        let metadata = applyDeclaredSpec(for: url)
        installBridgeScript(templateLanguage: metadata.resolvedLanguage)
        webView.loadLocalHTMLFile(url)
    }

    /// 卸载当前页面并清空当前文件（当前模板被删除时使用）。
    func clearHTML() {
        broadcast(.sessionEnded())
        currentURL = nil
        sessionSpecOverrides = nil
        panelState = .object([:])
        stateRevision = 0
        resetTransientWindowStyle()
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
        updateFileWatcher()
        hideWindow()
        notifyStatusChanged()
    }

    // MARK: - 声明式窗口属性

    /// HTML meta 的窗口属性（不含 CLI override）。
    @discardableResult
    private func applyDeclaredSpec(for url: URL) -> HTMLTemplateMetadata {
        // 与模板库同一套有效元数据：HTML meta > 模板目录默认尺寸
        let metadata = TemplateStore.effectiveMetadata(for: url)
        applyWindowSpec(metadata.windowSpec.merging(overrides: sessionSpecOverrides))
        return metadata
    }

    /// 每次导航前重装 documentStart 脚本；模板语言随文件变化。
    private func installBridgeScript(templateLanguage: String?) {
        userContentController.removeAllUserScripts()
        userContentController.addUserScript(WKUserScript(
            source: JSBridge.injectionScript(
                appLanguage: LanguageTag.appLanguage,
                languages: LanguageTag.templatePreferredLanguages,
                templateLanguage: templateLanguage,
                session: sessionID,
                initialState: panelState
            ),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
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
        // 菜单栏弹出时位置由状态栏图标锚定，声明的位置不生效；尺寸仍需应用。
        if displayMode == .menuBar {
            if panel.isVisible {
                anchorMenuBarPopover(requestedSize: size)
            } else if let size {
                resizeHiddenPanel(to: size)
            }
            return
        }

        guard let target = resolvedFrame(size: size, position: position),
              !target.equalTo(panel.frame) else { return }
        applyProgrammaticFrame(target)
    }

    /// 菜单栏模式下窗口隐藏时只预置尺寸，首次弹出由几何计算定位。
    private func resizeHiddenPanel(to size: WindowSize) {
        guard let target = resolvedFrame(size: size, position: nil),
              !target.equalTo(panel.frame) else { return }
        applyProgrammaticFrame(target)
    }

    /// 当前屏幕内的目标 frame；声明位置的解析规则只在这里定义。
    private func resolvedFrame(size: WindowSize?, position: WindowPosition?) -> NSRect? {
        guard let visible = (panel.screen ?? NSScreen.main)?.visibleFrame else { return nil }
        let resolved = WindowGeometry.resolve(
            size: size,
            position: position,
            current: WindowFrame(panel.frame),
            screen: WindowFrame(visible)
        )
        return resolved.nsRect
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
        var event = event
        if event.session == nil {
            event.session = sessionID
        }
        onControlEvent?(event)
    }

    // MARK: - 共享状态

    /// 页面 pinshell.setState：整体替换快照。
    func setPanelState(_ state: JSONValue) {
        panelState = state
        stateRevision += 1
        broadcast(.stateSnapshot(state))
        notifyStatusChanged()
    }

    /// 页面 pinshell.patchState：按 RFC 7386 合并补丁。
    func patchPanelState(_ patch: JSONValue) {
        panelState = panelState.applyingMergePatch(patch)
        stateRevision += 1
        broadcast(.stateDelta(patch))
        notifyStatusChanged()
    }

    func stateSnapshot() -> JSONValue {
        panelState
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
        let script = "window.__pinshellFetchResult(\(JSLiteral.string(id)), "
            + "\(ok ? "true" : "false"), "
            + "\(JSLiteral.string(body)), \(JSLiteral.string(error)));"
        webView.evaluateJavaScript(script, completionHandler: nil)
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
        // 通知只作变化信号，观察者（菜单项/控制台/WebView）从 AppState 读状态
        NotificationCenter.default.post(name: .pinshellPassthroughChanged, object: nil)
        syncPassthroughUI()
        notifyStatusChanged()
    }

    /// 从 AppState + 展示方式派生全部穿透 UI（窗口/拖拽手柄），init 与切换共用一条路径。
    /// 菜单栏弹出时强制交互，否则面板无法点击。
    private func syncPassthroughUI() {
        let enabled = effectivePassthroughEnabled
        panel.ignoresMouseEvents = enabled   // 窗口级开关：穿透 + 禁拖动一次生效
        grip.isHidden = enabled || displayMode == .menuBar
    }

    func togglePassthrough() {
        setPassthrough(!AppState.passthroughEnabled)
    }

    /// 预设四角：保持当前尺寸，贴到所在屏幕可见区域角落（默认 24pt 边距）
    func moveToCorner(_ corner: WindowAnchor) {
        guard displayMode == .desktop else { return }   // 菜单栏模式位置由图标锚定
        guard let visible = (panel.screen ?? NSScreen.main)?.visibleFrame else { return }
        let frame = WindowGeometry.resolve(
            size: nil,
            position: .anchor(corner),
            current: WindowFrame(panel.frame),
            screen: WindowFrame(visible)
        )
        panel.setFrame(frame.nsRect, display: true)
        notifyStatusChanged()
    }

    // MARK: - 状态

    /// 状态变化广播：控制台据此刷新状态胶囊与详情。
    private func notifyStatusChanged() {
        NotificationCenter.default.post(name: .pinshellStatusChanged, object: nil)
    }

    func status() -> JSONValue {
        let frame = panel.frame
        return .object([
            "file": currentURL.map { .string($0.path) } ?? .null,
            "session": .string(sessionID),
            "stateRevision": .number(Double(stateRevision)),
            "visible": .bool(panel.isVisible),
            "watching": .bool(watchEnabled && fileWatcher != nil),
            "displayMode": .string(displayMode.rawValue),
            "passthrough": .bool(effectivePassthroughEnabled),
            "opacity": .number(Double(panel.alphaValue)),
            "radius": .number(Double(currentRadius)),
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

    /// 拖动/缩放期间 didMove/didResize 以显示刷新率触发：防抖后一次性落盘。
    /// 菜单栏弹出模式的位置由图标决定，不能写进桌面 frame。
    @objc private func persistFrame() {
        guard displayMode == .desktop, !isApplyingProgrammaticFrame else { return }
        framePersistWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.displayMode == .desktop else { return }
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
        let frame = WindowGeometry.resolve(
            size: size,
            position: .anchor(.bottomRight),
            current: WindowFrame(x: 0, y: 0, width: size.width, height: size.height),
            screen: WindowFrame(vf)
        )
        return frame.nsRect
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
