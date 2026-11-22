import Foundation
import PinShellCore

/// PinShell MCP 2.0 stdio server.
///
/// 由 agent 以子进程方式启动：`PinShell mcp`。
/// stdout 只写 JSON-RPC；日志写 stderr。所有窗口操作复用本机 control socket，
/// 因此与 CLI 共享同一套权限和状态。
final class MCPServer {
    private let eventStream = MCPEventStream()
    private let toolSet = MCPToolSet()

    func run() -> Int32 {
        while let line = readLine(strippingNewline: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard let data = trimmed.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                sendError(id: nil, code: -32700, message: "Parse error")
                continue
            }
            handle(object)
        }
        return 0
    }

    static func printHelp() {
        let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: "PinShell")
        let config = MCPClient.serverConfigurationJSON(executable: executable, pretty: false)
        let message = """
        PinShell MCP 2.0 server (stdio)

        Add to your MCP client configuration:
        \(config)

        Tools: \(MCPToolSet.all.map(\.name).joined(separator: ", "))
        Prompts: \(MCPPromptCatalog.names.joined(separator: ", "))
        """
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    }

    // MARK: - JSON-RPC

    private func handle(_ request: [String: Any]) {
        guard let method = request["method"] as? String else {
            sendError(id: request["id"], code: -32600, message: "Invalid Request")
            return
        }

        // notifications（initialized / cancelled 等）无需响应
        guard let id = request["id"], !(id is NSNull) else { return }

        switch method {
        case "initialize":
            handleInitialize(id: id, params: request["params"] as? [String: Any])
        case "ping":
            sendResult(id: id, [:])
        case "tools/list":
            sendResult(id: id, ["tools": toolSet.definitions])
        case "tools/call":
            handleToolCall(id: id, params: request["params"] as? [String: Any])
        case "resources/list":
            sendResult(id: id, ["resources": []])
        case "prompts/list":
            sendResult(id: id, ["prompts": MCPPromptCatalog.definitions.map(Self.promptJSON)])
        case "prompts/get":
            handlePromptGet(id: id, params: request["params"] as? [String: Any])
        default:
            sendError(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    private func handleInitialize(id: Any, params: [String: Any]?) {
        let supported = ["2024-11-05", "2025-03-26", "2025-06-18"]
        let requested = params?["protocolVersion"] as? String
        let version = requested.flatMap { supported.contains($0) ? $0 : nil } ?? "2025-06-18"

        sendResult(id: id, [
            "protocolVersion": version,
            "capabilities": [
                "tools": ["listChanged": false],
                "prompts": ["listChanged": false]
            ],
            "serverInfo": [
                "name": MCPClient.serverName,
                "version": UpdateChecker.currentVersion
            ],
            "instructions": MCPPromptCatalog.serverInstructions
        ])
    }

    private func handleToolCall(id: Any, params: [String: Any]?) {
        guard let name = params?["name"] as? String else {
            sendError(id: id, code: -32602, message: "tools/call requires a tool name")
            return
        }
        let arguments = params?["arguments"] as? [String: Any] ?? [:]
        do {
            let text = try toolSet.execute(name: name, arguments: arguments,
                                           eventStream: eventStream)
            sendResult(id: id, [
                "content": [["type": "text", "text": text]],
                "isError": false
            ])
        } catch {
            sendResult(id: id, [
                "content": [["type": "text", "text": error.localizedDescription]],
                "isError": true
            ])
        }
    }

    // MARK: - Prompts

    private func handlePromptGet(id: Any, params: [String: Any]?) {
        guard let name = params?["name"] as? String, !name.isEmpty else {
            sendError(id: id, code: -32602, message: "prompts/get requires a prompt name")
            return
        }

        var arguments: [String: String] = [:]
        if let raw = params?["arguments"] as? [String: Any] {
            for (key, value) in raw {
                if let string = value as? String {
                    arguments[key] = string
                } else if let number = value as? NSNumber {
                    arguments[key] = number.stringValue
                }
            }
        }

        do {
            let prompt = try MCPPromptCatalog.render(name: name, arguments: arguments)
            sendResult(id: id, [
                "description": prompt.description,
                "messages": [[
                    "role": "user",
                    "content": ["type": "text", "text": prompt.text]
                ]]
            ])
        } catch {
            sendError(id: id, code: -32602, message: error.localizedDescription)
        }
    }

    private static func promptJSON(_ prompt: MCPPromptDefinition) -> [String: Any] {
        let arguments: [[String: Any]] = prompt.arguments.map { argument in
            [
                "name": argument.name,
                "description": argument.description,
                "required": argument.required
            ]
        }
        return [
            "name": prompt.name,
            "title": prompt.title,
            "description": prompt.description,
            "arguments": arguments
        ]
    }

    // MARK: - 输出

    private func sendResult(id: Any, _ result: [String: Any]) {
        write(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func sendError(id: Any?, code: Int, message: String) {
        var payload: [String: Any] = [
            "jsonrpc": "2.0",
            "error": ["code": code, "message": message]
        ]
        if let id { payload["id"] = id }
        write(payload)
    }

    private func write(_ object: [String: Any]) {
        let json = ControlWire.jsonText(JSONValue(any: object))
        FileHandle.standardOutput.write(Data((json + "\n").utf8))
    }
}

// MARK: - Tools

struct MCPToolSet {
    static let all: [MCPTool] = [
        MCPTool(
            name: "pinshell_show",
            description: "Show a local HTML file in the PinShell overlay. The file can declare window size/position/passthrough/opacity/radius via <meta name=\"pinshell:*\">.",
            properties: [
                "path": ["type": "string", "description": "Absolute or relative path to an HTML file."],
                "watch": ["type": "boolean", "description": "Hot-reload when the file changes."],
                "wait": ["type": "boolean", "description": "Wait until the page finishes loading."],
                "size": ["type": "string", "description": "Optional window size, e.g. 320x120."],
                "position": ["type": "string", "description": "Optional anchor (e.g. bottom-right) or absolute x,y."],
                "passthrough": ["type": "string", "enum": ["on", "off"], "description": "Click-through mode."],
                "opacity": ["type": "number", "minimum": 0, "maximum": 1],
                "radius": ["type": "number", "minimum": 0]
            ],
            required: ["path"]
        ),
        MCPTool(
            name: "pinshell_html",
            description: "Render generated HTML directly in the overlay. Writes the HTML to PinShell's agent folder and shows it. Use this to display information or UI to the user without managing files.",
            properties: [
                "html": ["type": "string", "description": "Complete HTML document."],
                "name": ["type": "string", "description": "File name (default panel.html)."],
                "watch": ["type": "boolean", "description": "Hot-reload when the file changes."],
                "wait": ["type": "boolean", "description": "Wait until the page finishes loading (default true)."],
                "size": ["type": "string"],
                "position": ["type": "string"],
                "passthrough": ["type": "string", "enum": ["on", "off"]],
                "opacity": ["type": "number", "minimum": 0, "maximum": 1],
                "radius": ["type": "number", "minimum": 0]
            ],
            required: ["html"]
        ),
        MCPTool(
            name: "pinshell_eval",
            description: "Evaluate JavaScript in the current overlay page and return the JSON result. Use it to update DOM content.",
            properties: [
                "script": ["type": "string", "description": "JavaScript expression or statements."]
            ],
            required: ["script"]
        ),
        MCPTool(
            name: "pinshell_emit",
            description: "Dispatch a pinshell:event CustomEvent to the current page. HTML can subscribe with pinshell.on(name, callback).",
            properties: [
                "event": ["type": "string"],
                "data": ["description": "Any JSON value delivered as event.detail.data."]
            ],
            required: ["event"]
        ),
        MCPTool(
            name: "pinshell_set",
            description: "Update the current overlay window (size/position/passthrough/opacity/radius).",
            properties: [
                "size": ["type": "string"],
                "position": ["type": "string"],
                "passthrough": ["type": "string", "enum": ["on", "off"]],
                "opacity": ["type": "number", "minimum": 0, "maximum": 1],
                "radius": ["type": "number", "minimum": 0]
            ],
            required: []
        ),
        MCPTool(
            name: "pinshell_status",
            description: "Return the current overlay status (file, frame, passthrough, opacity, radius, watch state).",
            properties: [:],
            required: []
        ),
        MCPTool(
            name: "pinshell_templates",
            description: "List auto-discovered templates with title, subtitle, size and path.",
            properties: [:],
            required: []
        ),
        MCPTool(
            name: "pinshell_template_read",
            description: "Read a template HTML file from PinShell's templates folder. Use pinshell_templates to see available names.",
            properties: [
                "name": ["type": "string", "description": "Template file name, e.g. todo.html."]
            ],
            required: ["name"]
        ),
        MCPTool(
            name: "pinshell_template_write",
            description: "Create or overwrite a template HTML file in PinShell's templates folder. The console refreshes automatically, and the overlay reloads if this template is currently shown.",
            properties: [
                "name": ["type": "string", "description": "Template file name, e.g. todo.html."],
                "html": ["type": "string", "description": "Complete HTML document."]
            ],
            required: ["name", "html"]
        ),
        MCPTool(
            name: "pinshell_template_delete",
            description: "Delete a template by file name. Built-in templates are remembered as removed so they are not re-seeded; restore them from the console toolbar.",
            properties: [
                "name": ["type": "string", "description": "Template file name, e.g. todo.html."]
            ],
            required: ["name"]
        ),
        MCPTool(
            name: "pinshell_template_show",
            description: "Show a template in the overlay. Accepts a template file name (e.g. todo.html) or its title. Optionally override size/position/passthrough/opacity/radius.",
            properties: [
                "name": ["type": "string", "description": "Template file name or title."],
                "size": ["type": "string", "description": "Optional window size, e.g. 320x120."],
                "position": ["type": "string", "description": "Optional anchor (e.g. bottom-right) or absolute x,y."],
                "passthrough": ["type": "string", "enum": ["on", "off"], "description": "Click-through mode."],
                "opacity": ["type": "number", "minimum": 0, "maximum": 1],
                "radius": ["type": "number", "minimum": 0],
                "wait": ["type": "boolean", "description": "Wait until the page finishes loading (default true)."]
            ],
            required: ["name"]
        ),
        MCPTool(
            name: "pinshell_poll_events",
            description: "Return user interaction events emitted by the page (pinshell.emit) since the last poll. Optionally wait for an event.",
            properties: [
                "timeout_ms": ["type": "integer", "minimum": 0, "maximum": 10000,
                               "description": "Maximum time to wait for an event."]
            ],
            required: []
        ),
        MCPTool(
            name: "pinshell_close",
            description: "Hide the overlay window.",
            properties: [:],
            required: []
        )
    ]

    let definitions: [[String: Any]] = MCPToolSet.all.map { tool in
        [
            "name": tool.name,
            "description": tool.description,
            "inputSchema": [
                "type": "object",
                "properties": tool.properties,
                "required": tool.required
            ]
        ]
    }

    func execute(name: String, arguments: [String: Any],
                 eventStream: MCPEventStream) throws -> String {
        switch name {
        case "pinshell_show":
            let path = try requiredString("path", in: arguments)
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
            guard url.isRegularFile else {
                throw MCPToolError("File not found: \(path)")
            }
            var args: [String: JSONValue] = ["path": .string(url.path)]
            copyCommonArguments(from: arguments, into: &args)
            let wait = boolValue(arguments["wait"]) ?? false
            let result = try control("show", args: args, timeout: wait ? 20 : 10)
            return ControlWire.jsonText(result)

        case "pinshell_html":
            let html = try requiredString("html", in: arguments)
            let rawName = (arguments["name"] as? String) ?? "panel.html"
            let fileURL = Self.agentFileURL(name: rawName)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            do {
                try Data(html.utf8).write(to: fileURL, options: .atomic)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                       ofItemAtPath: fileURL.path)
            } catch {
                throw MCPToolError("Cannot write agent HTML: \(error.localizedDescription)")
            }

            var args: [String: JSONValue] = ["path": .string(fileURL.path)]
            copyCommonArguments(from: arguments, into: &args)
            let wait = boolValue(arguments["wait"]) ?? true
            args["wait"] = .bool(wait)
            let result = try control("show", args: args, timeout: wait ? 20 : 10)
            var object = result.objectValue ?? [:]
            object["path"] = .string(fileURL.path)
            return ControlWire.jsonText(.object(object))

        case "pinshell_eval":
            let script = try requiredString("script", in: arguments)
            let result = try control("eval", args: ["script": .string(script)])
            return ControlWire.jsonText(result["result"] ?? .null)

        case "pinshell_emit":
            let event = try requiredString("event", in: arguments)
            var args: [String: JSONValue] = ["name": .string(event)]
            if let data = arguments["data"] {
                let value = JSONValue(any: data)
                args["data"] = .string(ControlWire.jsonText(value))
            }
            _ = try control("emit", args: args)
            return "emitted \(event)"

        case "pinshell_set":
            var args: [String: JSONValue] = [:]
            copyValueArguments(from: arguments, into: &args)
            guard !args.isEmpty else {
                throw MCPToolError("pinshell_set requires at least one property")
            }
            return ControlWire.jsonText(try control("set", args: args))

        case "pinshell_status":
            return ControlWire.jsonText(try control("status"))

        case "pinshell_templates":
            return ControlWire.jsonText(try control("templates"))

        case "pinshell_template_read":
            let name = try requiredString("name", in: arguments)
            let result = try control("template-read", args: ["name": .string(name)])
            guard let content = result["content"]?.stringValue else {
                throw MCPToolError("Template read returned no content")
            }
            return content

        case "pinshell_template_write":
            let name = try requiredString("name", in: arguments)
            let html = try requiredString("html", in: arguments)
            let result = try control("template-write", args: [
                "name": .string(name),
                "html": .string(html)
            ])
            return ControlWire.jsonText(result)

        case "pinshell_template_delete":
            let name = try requiredString("name", in: arguments)
            let result = try control("template-delete", args: ["name": .string(name)])
            return ControlWire.jsonText(result)

        case "pinshell_template_show":
            let name = try requiredString("name", in: arguments)
            let listed = try control("templates")
            let templates = listed["templates"]?.arrayValue ?? []
            let match = try Self.matchTemplate(named: name, in: templates)
            guard let path = match["path"]?.stringValue else {
                throw MCPToolError("Template has no file path: \(name)")
            }

            var args: [String: JSONValue] = ["path": .string(path)]
            copyValueArguments(from: arguments, into: &args)
            let wait = boolValue(arguments["wait"]) ?? true
            args["wait"] = .bool(wait)
            let result = try control("show", args: args, timeout: wait ? 20 : 10)

            var object = result.objectValue ?? [:]
            object["template"] = .object([
                "file": match["file"] ?? .null,
                "name": match["name"] ?? .null,
                "path": .string(path)
            ])
            return ControlWire.jsonText(.object(object))

        case "pinshell_poll_events":
            let timeoutMS = min(max(intValue(arguments["timeout_ms"]) ?? 0, 0), 10_000)
            let events = eventStream.poll(timeout: Double(timeoutMS) / 1000)
            return ControlWire.jsonText(events)

        case "pinshell_close":
            _ = try control("close")
            return "overlay hidden"

        default:
            throw MCPToolError("Unknown tool: \(name)")
        }
    }

    // MARK: - 参数

    private func requiredString(_ key: String, in arguments: [String: Any]) throws -> String {
        guard let value = arguments[key] as? String, !value.isEmpty else {
            throw MCPToolError("Missing required argument: \(key)")
        }
        return value
    }

    private func copyCommonArguments(from arguments: [String: Any], into args: inout [String: JSONValue]) {
        copyValueArguments(from: arguments, into: &args)
        if let watch = boolValue(arguments["watch"]) { args["watch"] = .bool(watch) }
        if let wait = boolValue(arguments["wait"]) { args["wait"] = .bool(wait) }
    }

    private func copyValueArguments(from arguments: [String: Any], into args: inout [String: JSONValue]) {
        if let size = arguments["size"] as? String { args["size"] = .string(size) }
        if let position = arguments["position"] as? String { args["position"] = .string(position) }
        if let passthrough = arguments["passthrough"] as? String {
            args["passthrough"] = .string(passthrough)
        }
        if let opacity = numberValue(arguments["opacity"]) {
            args["opacity"] = .string(NumberFormat.text(opacity, fractionDigits: 2))
        }
        if let radius = numberValue(arguments["radius"]) {
            args["radius"] = .string(NumberFormat.text(radius, fractionDigits: 2))
        }
    }

    private func boolValue(_ value: Any?) -> Bool? {
        guard let value else { return nil }
        return JSONValue(any: value).boolValue
    }

    private func numberValue(_ value: Any?) -> Double? {
        guard let value else { return nil }
        return JSONValue(any: value).doubleValue
    }

    private func intValue(_ value: Any?) -> Int? {
        guard let value else { return nil }
        return JSONValue(any: value).intValue
    }

    // MARK: - 控制通道

    private func control(_ cmd: String,
                         args: [String: JSONValue] = [:],
                         timeout: TimeInterval = 10) throws -> JSONValue {
        do {
            let response = try ControlClient.request(ControlRequest(cmd: cmd, args: args),
                                                     timeout: timeout)
            guard response.ok else {
                throw MCPToolError(response.error?.message ?? "PinShell command failed")
            }
            return response.result ?? .object([:])
        } catch let error as MCPToolError {
            throw error
        } catch {
            throw MCPToolError(error.localizedDescription)
        }
    }

    // MARK: - 编码

    /// 按文件名（可省略扩展名）或标题匹配模板；找不到时列出可用模板。
    private static func matchTemplate(named query: String,
                                      in templates: [JSONValue]) throws -> [String: JSONValue] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else {
            throw MCPToolError("Template name is empty")
        }

        func field(_ template: JSONValue, _ key: String) -> String {
            template[key]?.stringValue?.lowercased() ?? ""
        }

        let withExtension = (needle.hasSuffix(".html") || needle.hasSuffix(".htm"))
            ? needle
            : needle + ".html"

        if let match = templates.first(where: { template in
            let file = field(template, "file")
            return file == needle || file == withExtension
        }) {
            return match.objectValue ?? [:]
        }

        if let match = templates.first(where: { field($0, "name") == needle }) {
            return match.objectValue ?? [:]
        }

        let partial = templates.filter { template in
            field(template, "file").contains(needle) || field(template, "name").contains(needle)
        }
        if partial.count == 1, let match = partial.first?.objectValue {
            return match
        }

        let available = templates.compactMap { template -> String? in
            guard let file = template["file"]?.stringValue else { return nil }
            if let name = template["name"]?.stringValue, !name.isEmpty {
                return "\(file) (\(name))"
            }
            return file
        }
        throw MCPToolError("Template not found: \(query). Available: "
            + (available.isEmpty ? "none" : available.joined(separator: ", ")))
    }

    private static func agentFileURL(name: String) -> URL {
        let sanitized = name
            .replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
        let base = sanitized.isEmpty ? "panel" : sanitized
        let file = base.lowercased().hasSuffix(".html") ? base : base + ".html"
        return ControlEndpoint.applicationDirectory()
            .appendingPathComponent("agent", isDirectory: true)
            .appendingPathComponent(file)
    }

}

struct MCPTool {
    let name: String
    let description: String
    let properties: [String: Any]
    let required: [String]
}

private struct MCPToolError: Error, LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// MARK: - 事件流

/// 后台订阅 `listen`，把页面事件排队供 `pinshell_poll_events` 取走。
final class MCPEventStream {
    private let condition = NSCondition()
    private var events: [ControlEvent] = []
    private var started = false
    private let maxEvents = 500

    func poll(timeout: TimeInterval) -> [ControlEvent] {
        startIfNeeded()
        let deadline = Date().addingTimeInterval(timeout)

        condition.lock()
        defer { condition.unlock() }
        while events.isEmpty && timeout > 0 {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { break }
            condition.wait(until: min(deadline, Date().addingTimeInterval(remaining)))
        }
        let result = events
        events.removeAll()
        return result
    }

    private func startIfNeeded() {
        condition.lock()
        if started {
            condition.unlock()
            return
        }
        started = true
        condition.unlock()

        let thread = Thread { [weak self] in self?.run() }
        thread.name = "PinShell.MCP.Events"
        thread.start()
    }

    private func run() {
        while true {
            do {
                let (fd, _) = try ControlClient.openListenStream()
                defer { close(fd) }
                while let line = try ControlClient.readLine(fd: fd, timeout: nil) {
                    guard let event = try? ControlWire.decodeLine(line, as: ControlEvent.self) else {
                        continue
                    }
                    condition.lock()
                    events.append(event)
                    if events.count > maxEvents {
                        events.removeFirst(events.count - maxEvents)
                    }
                    condition.broadcast()
                    condition.unlock()
                }
            } catch {
                // App 未运行/退出：稍后重试
            }
            Thread.sleep(forTimeInterval: 1)
        }
    }
}
