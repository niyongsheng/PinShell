import AppKit
import Foundation
import PinShellCore

/// 把 CLI 请求翻译成窗口/页面操作，并把页面事件广播给 listen 客户端。
final class ControlHost {
    private weak var windowController: OverlayWindowController?
    private weak var server: ControlServer?

    private struct PendingShow {
        let connection: ControlConnection
        let requestID: String
        let timeout: DispatchWorkItem
    }

    /// show --wait：等 didFinish 再回复
    private var pendingShow: PendingShow?

    /// 模板扫描/读写串行执行，避免阻塞主线程，同时保持操作顺序。
    private let fileQueue = DispatchQueue(label: "PinShell.ControlHost.Files",
                                          qos: .utility)

    /// 当前 `listen` 订阅数；页面据此显示「AI 在线」。
    private var listenerCount = 0

    init(windowController: OverlayWindowController, server: ControlServer) {
        self.windowController = windowController
        self.server = server

        server.onRequest = { [weak self] request, connection in
            self?.handle(request, from: connection)
        }
        // 先挂回调再取快照：避免在两步之间漏掉新订阅。
        server.onListenerCountChanged = { [weak self] count in
            DispatchQueue.main.async {
                guard let self else { return }
                self.listenerCount = count
                self.pushAgentPresence()
            }
        }
        listenerCount = server.listenerSnapshot()
        windowController.onControlEvent = { [weak server] event in
            server?.broadcast(event)
        }
        windowController.onPageLoaded = { [weak self] in
            self?.finishPendingShow()
            self?.pushAgentPresence()
        }
        windowController.onPageLoadFailed = { [weak self] error in
            self?.finishPendingShow(code: "load_failed", message: error.localizedDescription)
        }
    }

    // MARK: - 分发

    private func handle(_ request: ControlRequest, from connection: ControlConnection) {
        switch request.cmd {
        case "show": handleShow(request, connection: connection)
        case "set": handleSet(request, connection: connection)
        case "reload": handleReload(request, connection: connection)
        case "eval": handleEval(request, connection: connection)
        case "emit": handleEmit(request, connection: connection)
        case "listen":
            connection.subscribe()
            connection.send(.success(id: request.id, result: .object(["subscribed": .bool(true)])))
        case "events":
            handleEvents(request, connection: connection)
        case "state":
            connection.send(.success(id: request.id, result: stateResult()))
        case "status":
            connection.send(.success(id: request.id, result: statusResult()))
        case "templates":
            handleTemplates(request, connection: connection)
        case "template-read":
            handleTemplateRead(request, connection: connection)
        case "template-write":
            handleTemplateWrite(request, connection: connection)
        case "template-delete":
            handleTemplateDelete(request, connection: connection)
        case "close":
            windowController?.hideWindow()
            connection.send(.success(id: request.id, result: statusResult()))
        case "quit":
            connection.send(.success(id: request.id, result: .object(["quitting": .bool(true)])))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.terminate(nil)
            }
        default:
            connection.send(.failure(id: request.id, code: "unknown_command",
                                     message: "unknown command: \(request.cmd)"))
        }
    }

    // MARK: - show / set

    private func handleShow(_ request: ControlRequest, connection: ControlConnection) {
        guard let rawPath = string(request, "path"), !rawPath.isEmpty else {
            connection.send(.failure(id: request.id, code: "invalid_args",
                                     message: "show requires a file path"))
            return
        }
        let url = URL(fileURLWithPath: rawPath).standardizedFileURL
        guard url.isRegularFile else {
            connection.send(.failure(id: request.id, code: "not_found",
                                     message: "file not found: \(rawPath)"))
            return
        }

        let spec: WindowSpec
        switch parseSpec(request) {
        case .success(let parsed):
            spec = parsed
        case .failure(let error):
            connection.send(.failure(id: request.id, code: error.code, message: error.message))
            return
        }

        finishPendingShow(code: "superseded",
                          message: "superseded by a newer show command")

        let watch = bool(request, "watch") ?? false
        let wait = bool(request, "wait") ?? false
        windowController?.setWatching(watch)
        windowController?.loadHTML(url, specOverride: spec.isEmpty ? nil : spec)

        if wait {
            let timeout = DispatchWorkItem { [weak self] in
                self?.finishPendingShow(code: "load_failed",
                                        message: "HTML did not finish loading in time")
            }
            pendingShow = PendingShow(connection: connection, requestID: request.id, timeout: timeout)
            DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)
        } else {
            connection.send(.success(id: request.id, result: statusResult()))
        }
    }

    private func handleSet(_ request: ControlRequest, connection: ControlConnection) {
        let spec: WindowSpec
        switch parseSpec(request) {
        case .success(let parsed):
            spec = parsed
        case .failure(let error):
            connection.send(.failure(id: request.id, code: error.code, message: error.message))
            return
        }

        guard !spec.isEmpty else {
            connection.send(.failure(id: request.id, code: "no_changes",
                                     message: "set requires at least one property"))
            return
        }
        windowController?.applyControlSpec(spec)
        connection.send(.success(id: request.id, result: statusResult()))
    }

    private func handleReload(_ request: ControlRequest, connection: ControlConnection) {
        windowController?.reloadHTML()
        connection.send(.success(id: request.id, result: statusResult()))
    }

    // MARK: - 模板文件（受限路径：模板目录内平铺 .html/.htm）

    private func handleTemplates(_ request: ControlRequest, connection: ControlConnection) {
        fileQueue.async {
            connection.send(.success(id: request.id, result: Self.templatesResult()))
        }
    }

    private func handleTemplateRead(_ request: ControlRequest, connection: ControlConnection) {
        guard let name = string(request, "name"), !name.isEmpty else {
            connection.send(.failure(id: request.id, code: "invalid_args",
                                     message: "template-read requires a name"))
            return
        }
        let directory = TemplateStore.userTemplatesDirectory()
        fileQueue.async {
            do {
                let result = try TemplateStorage.read(name: name, in: directory)
                connection.send(.success(id: request.id, result: .object([
                    "path": .string(result.url.path),
                    "content": .string(result.content),
                ])))
            } catch {
                Self.sendTemplateFailure(error, id: request.id, connection: connection)
            }
        }
    }

    private func handleTemplateWrite(_ request: ControlRequest, connection: ControlConnection) {
        guard let name = string(request, "name"), !name.isEmpty,
              let html = string(request, "html") else {
            connection.send(.failure(id: request.id, code: "invalid_args",
                                     message: "template-write requires name and html"))
            return
        }
        let directory = TemplateStore.userTemplatesDirectory()
        fileQueue.async { [weak self] in
            do {
                let url = try TemplateStorage.write(name: name, html: html, in: directory)
                let bytes = html.utf8.count
                DispatchQueue.main.async {
                    guard let self else { return }
                    let isCurrent = self.windowController?.currentURL?.standardizedFileURL
                        == url.standardizedFileURL
                    if isCurrent { self.windowController?.reloadHTML() }
                    NotificationCenter.default.post(name: .pinshellTemplatesChanged, object: url)
                    connection.send(.success(id: request.id, result: .object([
                        "path": .string(url.path),
                        "bytes": .number(Double(bytes)),
                        "reloaded": .bool(isCurrent),
                    ])))
                }
            } catch {
                Self.sendTemplateFailure(error, id: request.id, connection: connection)
            }
        }
    }

    private func handleTemplateDelete(_ request: ControlRequest, connection: ControlConnection) {
        guard let name = string(request, "name"), !name.isEmpty else {
            connection.send(.failure(id: request.id, code: "invalid_args",
                                     message: "template-delete requires a name"))
            return
        }
        let directory = TemplateStore.userTemplatesDirectory()
        fileQueue.async { [weak self] in
            do {
                let url = try TemplateStorage.resolve(name: name, in: directory)
                let wasBuiltin = try TemplateStore.deleteTemplate(at: url)
                DispatchQueue.main.async {
                    guard let self else { return }
                    let isCurrent = self.windowController?.currentURL?.standardizedFileURL
                        == url.standardizedFileURL
                    if isCurrent { self.windowController?.clearHTML() }
                    connection.send(.success(id: request.id, result: .object([
                        "file": .string(url.lastPathComponent),
                        "path": .string(url.path),
                        "wasCurrent": .bool(isCurrent),
                        "builtin": .bool(wasBuiltin),
                    ])))
                }
            } catch {
                Self.sendTemplateFailure(error, id: request.id, connection: connection)
            }
        }
    }

    private static func sendTemplateFailure(_ error: Swift.Error, id: String,
                                            connection: ControlConnection) {
        let code: String
        if error is TemplateFilePolicy.Error {
            code = "invalid_name"
        } else if let storageError = error as? TemplateStorage.Error {
            switch storageError {
            case .notFound: code = "not_found"
            case .tooLarge: code = "too_large"
            }
        } else {
            code = "io_error"
        }
        connection.send(.failure(id: id, code: code,
                                 message: error.localizedDescription))
    }

    // MARK: - 页面交互

    private func handleEval(_ request: ControlRequest, connection: ControlConnection) {
        guard let script = string(request, "script") else {
            connection.send(.failure(id: request.id, code: "invalid_args",
                                     message: "eval requires a script"))
            return
        }
        guard let windowController else {
            connection.send(.failure(id: request.id, code: "no_page",
                                     message: "no page loaded"))
            return
        }
        windowController.evaluate(script: script) { result in
            switch result {
            case .success(let value):
                connection.send(.success(id: request.id, result: .object(["result": value])))
            case .failure(let error):
                connection.send(.failure(id: request.id, code: "js_error",
                                         message: error.message))
            }
        }
    }

    // MARK: - 事件重放 / 共享状态

    private func handleEvents(_ request: ControlRequest, connection: ControlConnection) {
        guard let server else {
            connection.send(.failure(id: request.id, code: "app_unavailable",
                                     message: "control server unavailable"))
            return
        }
        let since = max(int(request, "since") ?? 0, 0)
        let limit = min(max(int(request, "limit") ?? 200, 1), 1000)
        let epoch = string(request, "epoch")
        let types = stringSet(request, "types")
        let names = stringSet(request, "names")
        server.replayEvents(since: since, epoch: epoch, types: types, names: names,
                            limit: limit) { batch in
            connection.send(.success(id: request.id, result: batch.jsonValue))
        }
    }

    private func stateResult() -> JSONValue {
        .object([
            "session": .string(windowController?.sessionID ?? ""),
            "state": windowController?.stateSnapshot() ?? .object([:]),
            "revision": .number(Double(windowController?.stateRevision ?? 0))
        ])
    }

    private func handleEmit(_ request: ControlRequest, connection: ControlConnection) {
        guard let name = string(request, "name"), !name.isEmpty else {
            connection.send(.failure(id: request.id, code: "invalid_args",
                                     message: "emit requires an event name"))
            return
        }

        var data = JSONValue.null
        if let raw = string(request, "data"), !raw.isEmpty {
            guard let bytes = raw.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: bytes, options: [.fragmentsAllowed]) else {
                connection.send(.failure(id: request.id, code: "invalid_json",
                                         message: "emit data must be valid JSON"))
                return
            }
            data = JSONValue(any: object)
        }

        windowController?.dispatchEvent(name: name, data: data)
        connection.send(.success(id: request.id, result: .object(["emitted": .bool(true)])))
    }

    /// 把 agent 订阅状态推给页面（宠物等模板用 agent:presence 显示在线状态）。
    private func pushAgentPresence() {
        windowController?.dispatchEvent(name: "agent:presence", data: .object([
            "online": .bool(listenerCount > 0),
            "count": .number(Double(listenerCount))
        ]))
    }

    // MARK: - 结果构造

    private func statusResult() -> JSONValue {
        var object: [String: JSONValue] = [:]
        if case .object(let status) = windowController?.status() {
            object = status
        }
        object["version"] = .string(UpdateChecker.currentVersion)
        object["pid"] = .number(Double(ProcessInfo.processInfo.processIdentifier))
        return .object(object)
    }

    private static func templatesResult() -> JSONValue {
        let templates = TemplateStore.load().map { item -> JSONValue in
            .object([
                "file": .string(item.file),
                "name": .string(item.name),
                "description": .string(item.description),
                "language": item.language.map { .string($0) } ?? .null,
                "path": .string(item.url.path),
                "size": .object([
                    "width": .number(item.size.width),
                    "height": .number(item.size.height)
                ]),
                "order": item.order == Int.max ? .null : .number(Double(item.order))
            ])
        }
        return .object(["templates": .array(templates)])
    }

    // MARK: - show --wait

    /// 结束等待中的 show：code 为 nil 表示成功，否则返回失败。
    private func finishPendingShow(code: String? = nil, message: String = "") {
        guard let pending = pendingShow else { return }
        pendingShow = nil
        pending.timeout.cancel()
        if let code {
            pending.connection.send(.failure(id: pending.requestID, code: code, message: message))
        } else {
            pending.connection.send(.success(id: pending.requestID, result: statusResult()))
        }
    }

    // MARK: - 参数

    private struct SpecParseError: Error {
        let code: String
        let message: String
    }

    /// show / set 共用的 size/position/passthrough/opacity/radius 解析。
    private func parseSpec(_ request: ControlRequest) -> Result<WindowSpec, SpecParseError> {
        var spec = WindowSpec()

        if let raw = string(request, "size") {
            guard let size = WindowSize.parse(raw) else {
                return .failure(SpecParseError(code: "invalid_args",
                                               message: "invalid --size: \(raw)"))
            }
            spec.size = size
        }
        if let raw = string(request, "position") {
            guard let position = WindowPosition.parse(raw) else {
                return .failure(SpecParseError(code: "invalid_args",
                                               message: "invalid --position: \(raw)"))
            }
            spec.position = position
        }
        if let raw = string(request, "passthrough") {
            guard let enabled = ValueParsing.bool(raw) else {
                return .failure(SpecParseError(code: "invalid_args",
                                               message: "invalid --passthrough: \(raw)"))
            }
            spec.passthrough = enabled
        }
        if let raw = string(request, "opacity") {
            guard let value = Double(raw), value.isFinite else {
                return .failure(SpecParseError(code: "invalid_args",
                                               message: "invalid --opacity: \(raw)"))
            }
            spec.opacity = min(max(value, 0), 1)
        }
        if let raw = string(request, "radius") {
            guard let value = Double(raw), value.isFinite, value >= 0 else {
                return .failure(SpecParseError(code: "invalid_args",
                                               message: "invalid --radius: \(raw)"))
            }
            spec.radius = value
        }
        return .success(spec)
    }

    private func string(_ request: ControlRequest, _ key: String) -> String? {
        request.args[key]?.stringValue
    }

    private func bool(_ request: ControlRequest, _ key: String) -> Bool? {
        request.args[key]?.boolValue
    }

    private func int(_ request: ControlRequest, _ key: String) -> Int? {
        request.args[key]?.intValue
    }

    private func stringSet(_ request: ControlRequest, _ key: String) -> Set<String>? {
        guard let values = request.args[key]?.arrayValue else { return nil }
        let strings = values.compactMap(\.stringValue).filter { !$0.isEmpty }
        return strings.isEmpty ? nil : Set(strings)
    }
}
