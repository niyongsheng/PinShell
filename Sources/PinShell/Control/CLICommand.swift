import Foundation
import Darwin
import PinShellCore

/// CLI 子命令解析与执行。无参数时返回 nil → 进入 App 宿主模式。
enum CLICommand {
    struct ShowOptions {
        var path: String
        var size: String?
        var position: String?
        var passthrough: String?
        var opacity: String?
        var radius: String?
        var watch = false
        var wait = false
        var json = false
    }

    struct SetOptions {
        var size: String?
        var position: String?
        var passthrough: String?
        var opacity: String?
        var radius: String?
        var json = false
    }

    case show(ShowOptions)
    case set(SetOptions)
    case reload(json: Bool)
    case eval(script: String, json: Bool)
    case emit(name: String, data: String?, json: Bool)
    case listen(json: Bool)
    case status(json: Bool)
    case templates(json: Bool)
    case close(json: Bool)
    case quit(json: Bool)
    case help
    case invalid(String)

    // MARK: - 解析

    private static let showValueFlags: Set<String> =
        ["--size", "--position", "--passthrough", "--opacity", "--radius"]
    private static let showSwitchFlags: Set<String> = ["--watch", "--wait", "--json"]
    private static let jsonSwitch: Set<String> = ["--json"]

    static func parse(_ args: [String]) -> CLICommand? {
        guard !args.isEmpty else { return nil }
        if args.contains("--help") || args.contains("-h") || args.first == "help" {
            return .help
        }

        let command = args[0]
        let rest = Array(args.dropFirst())
        switch command {
        case "show":
            return parseShow(rest)
        case "set":
            return parseSet(rest)
        case "reload":
            return parseSimple(rest) { .reload(json: $0) }
        case "listen":
            return parseSimple(rest) { .listen(json: $0) }
        case "status":
            return parseSimple(rest) { .status(json: $0) }
        case "templates":
            return parseSimple(rest) { .templates(json: $0) }
        case "close":
            return parseSimple(rest) { .close(json: $0) }
        case "quit":
            return parseSimple(rest) { .quit(json: $0) }
        case "eval":
            return parseEval(rest)
        case "emit":
            return parseEmit(rest)
        default:
            // 兼容旧用法：PinShell ./file.html
            if !command.hasPrefix("-"),
               FileManager.default.fileExists(atPath: command)
                || TemplateFilePolicy.isTemplateFile(named: command) {
                return parseShow(args)
            }
            return .invalid("unknown command: \(command)")
        }
    }

    private static func parseShow(_ args: [String]) -> CLICommand {
        parseCommand(args, valueFlags: showValueFlags, switchFlags: showSwitchFlags) { parsed in
            guard let path = parsed.positionals.first else {
                return .invalid("show requires a file path")
            }
            guard parsed.positionals.count == 1 else {
                return .invalid("unexpected arguments: \(parsed.positionals.dropFirst().joined(separator: " "))")
            }
            if let error = validateValues(parsed.values) { return .invalid(error) }
            return .show(ShowOptions(
                path: path,
                size: parsed.values["--size"],
                position: parsed.values["--position"],
                passthrough: parsed.values["--passthrough"],
                opacity: parsed.values["--opacity"],
                radius: parsed.values["--radius"],
                watch: parsed.switches.contains("--watch"),
                wait: parsed.switches.contains("--wait"),
                json: parsed.switches.contains("--json")
            ))
        }
    }

    private static func parseSet(_ args: [String]) -> CLICommand {
        parseCommand(args, valueFlags: showValueFlags, switchFlags: jsonSwitch) { parsed in
            guard parsed.positionals.isEmpty else {
                return .invalid("set does not take positional arguments")
            }
            if let error = validateValues(parsed.values) { return .invalid(error) }
            return .set(SetOptions(
                size: parsed.values["--size"],
                position: parsed.values["--position"],
                passthrough: parsed.values["--passthrough"],
                opacity: parsed.values["--opacity"],
                radius: parsed.values["--radius"],
                json: parsed.switches.contains("--json")
            ))
        }
    }

    private static func parseSimple(_ args: [String],
                                    make: (Bool) -> CLICommand) -> CLICommand {
        parseCommand(args, valueFlags: [], switchFlags: jsonSwitch) { parsed in
            guard parsed.positionals.isEmpty else {
                return .invalid("unexpected arguments: \(parsed.positionals.joined(separator: " "))")
            }
            return make(parsed.switches.contains("--json"))
        }
    }

    private static func parseEval(_ args: [String]) -> CLICommand {
        parseCommand(args, valueFlags: [], switchFlags: jsonSwitch) { parsed in
            let script = parsed.positionals.joined(separator: " ")
            guard !script.isEmpty else { return .invalid("eval requires a script") }
            return .eval(script: script, json: parsed.switches.contains("--json"))
        }
    }

    private static func parseEmit(_ args: [String]) -> CLICommand {
        parseCommand(args, valueFlags: [], switchFlags: jsonSwitch) { parsed in
            guard let name = parsed.positionals.first, !name.isEmpty else {
                return .invalid("emit requires an event name")
            }
            let data = parsed.positionals.dropFirst().joined(separator: " ")
            return .emit(name: name,
                         data: data.isEmpty ? nil : data,
                         json: parsed.switches.contains("--json"))
        }
    }

    /// 统一 parseArguments 的失败映射，避免每个子命令重复同一 switch。
    private static func parseCommand(_ args: [String],
                                     valueFlags: Set<String>,
                                     switchFlags: Set<String>,
                                     make: (ParsedArguments) -> CLICommand) -> CLICommand {
        switch parseArguments(args, valueFlags: valueFlags, switchFlags: switchFlags) {
        case .failure(let error):
            return .invalid(error.message)
        case .success(let parsed):
            return make(parsed)
        }
    }

    private static func validateValues(_ values: [String: String]) -> String? {
        if let raw = values["--size"], WindowSize.parse(raw) == nil {
            return "invalid --size: \(raw) (expected WxH, e.g. 240x80)"
        }
        if let raw = values["--position"], WindowPosition.parse(raw) == nil {
            return "invalid --position: \(raw) (expected anchor or x,y)"
        }
        if let raw = values["--passthrough"], ValueParsing.bool(raw) == nil {
            return "invalid --passthrough: \(raw) (expected on|off)"
        }
        if let raw = values["--opacity"] {
            guard let value = Double(raw), value.isFinite, (0...1).contains(value) else {
                return "invalid --opacity: \(raw) (expected 0..1)"
            }
        }
        if let raw = values["--radius"] {
            guard let value = Double(raw), value.isFinite, value >= 0 else {
                return "invalid --radius: \(raw) (expected >= 0)"
            }
        }
        return nil
    }

    private struct ParsedArguments {
        var positionals: [String] = []
        var values: [String: String] = [:]
        var switches: Set<String> = []
    }

    private struct ParseFailure: Error {
        let message: String
    }

    private static func parseArguments(_ args: [String],
                                       valueFlags: Set<String>,
                                       switchFlags: Set<String>) -> Result<ParsedArguments, ParseFailure> {
        var parsed = ParsedArguments()
        var index = 0
        while index < args.count {
            let arg = args[index]
            guard arg.hasPrefix("--") else {
                parsed.positionals.append(arg)
                index += 1
                continue
            }

            let name: String
            let inlineValue: String?
            if let equals = arg.firstIndex(of: "=") {
                name = String(arg[arg.startIndex..<equals])
                inlineValue = String(arg[arg.index(after: equals)...])
            } else {
                name = arg
                inlineValue = nil
            }

            if valueFlags.contains(name) {
                if let inlineValue {
                    parsed.values[name] = inlineValue
                } else {
                    guard index + 1 < args.count else {
                        return .failure(ParseFailure(message: "missing value for \(name)"))
                    }
                    parsed.values[name] = args[index + 1]
                    index += 1
                }
            } else if switchFlags.contains(name) {
                if let inlineValue, !inlineValue.isEmpty {
                    return .failure(ParseFailure(message: "\(name) does not take a value"))
                }
                parsed.switches.insert(name)
            } else {
                return .failure(ParseFailure(message: "unknown option: \(name)"))
            }
            index += 1
        }
        return .success(parsed)
    }

    // MARK: - 执行

    static func run(_ command: CLICommand) -> Int32 {
        switch command {
        case .help:
            printHelp()
            return 0
        case .invalid(let message):
            failUsage(message)
            return 1
        case .show(let options):
            return runShow(options)
        case .set(let options):
            return runSet(options)
        case .reload(let json):
            return perform(ControlRequest(cmd: "reload"), json: json) { printStatus($0) }
        case .eval(let script, let json):
            return perform(ControlRequest(cmd: "eval", args: ["script": .string(script)]),
                           json: json) { result in
                let value = result["result"] ?? .null
                if let string = value.stringValue {
                    print(string)
                } else {
                    printJSON(value)
                }
            }
        case .emit(let name, let data, let json):
            var args: [String: JSONValue] = ["name": .string(name)]
            if let data { args["data"] = .string(data) }
            return perform(ControlRequest(cmd: "emit", args: args), json: json) { _ in
                print("emitted \(name)")
            }
        case .listen(let json):
            return runListen(json: json)
        case .status(let json):
            return perform(ControlRequest(cmd: "status"), json: json) { printStatus($0) }
        case .templates(let json):
            return perform(ControlRequest(cmd: "templates"), json: json) { printTemplates($0) }
        case .close(let json):
            return perform(ControlRequest(cmd: "close"), json: json) { _ in
                print("overlay hidden")
            }
        case .quit(let json):
            return perform(ControlRequest(cmd: "quit"), json: json) { _ in
                print("PinShell quitting")
            }
        }
    }

    private static func runShow(_ options: ShowOptions) -> Int32 {
        let expanded = (options.path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded).standardizedFileURL
        guard url.isRegularFile else {
            failUsage("file not found: \(options.path)", json: options.json)
            return 1
        }

        var args: [String: JSONValue] = ["path": .string(url.path)]
        if let size = options.size { args["size"] = .string(size) }
        if let position = options.position { args["position"] = .string(position) }
        if let passthrough = options.passthrough { args["passthrough"] = .string(passthrough) }
        if let opacity = options.opacity { args["opacity"] = .string(opacity) }
        if let radius = options.radius { args["radius"] = .string(radius) }
        args["watch"] = .bool(options.watch)
        args["wait"] = .bool(options.wait)

        let request = ControlRequest(cmd: "show", args: args)
        return perform(request, json: options.json, timeout: options.wait ? 20 : 10) { result in
            printStatus(result)
        }
    }

    private static func runSet(_ options: SetOptions) -> Int32 {
        var args: [String: JSONValue] = [:]
        if let size = options.size { args["size"] = .string(size) }
        if let position = options.position { args["position"] = .string(position) }
        if let passthrough = options.passthrough { args["passthrough"] = .string(passthrough) }
        if let opacity = options.opacity { args["opacity"] = .string(opacity) }
        if let radius = options.radius { args["radius"] = .string(radius) }
        guard !args.isEmpty else {
            failUsage("set requires at least one property", json: options.json)
            return 1
        }
        return perform(ControlRequest(cmd: "set", args: args), json: options.json) { result in
            printStatus(result)
        }
    }

    private static func runListen(json: Bool) -> Int32 {
        do {
            let (fd, _) = try ControlClient.openListenStream()
            defer { ControlClient.closeConnection(fd) }
            while let line = try ControlClient.readLine(fd: fd, timeout: nil) {
                if json {
                    print(String(decoding: line, as: UTF8.self))
                } else {
                    printHumanEvent(line)
                }
            }
            return 0
        } catch let error as ControlClientError {
            printError(error.localizedDescription)
            return error.exitCode
        } catch {
            printError(error.localizedDescription)
            return 3
        }
    }

    // MARK: - 输出

    private static func perform(_ request: ControlRequest,
                                json: Bool,
                                timeout: TimeInterval = 10,
                                human: (JSONValue) -> Void) -> Int32 {
        do {
            let response = try ControlClient.request(request, timeout: timeout)
            guard response.ok else {
                let code = response.error?.code ?? "command_failed"
                let message = response.error?.message ?? "command failed"
                if json {
                    printJSON(.object(["error": .object([
                        "code": .string(code),
                        "message": .string(message)
                    ])]))
                } else {
                    printError(message)
                }
                return 3
            }
            let result = response.result ?? .object([:])
            if json {
                printJSON(result)
            } else {
                human(result)
            }
            return 0
        } catch let error as ControlClientError {
            printError(error.localizedDescription)
            return error.exitCode
        } catch {
            printError(error.localizedDescription)
            return 3
        }
    }

    private static func printStatus(_ result: JSONValue) {
        print("file: \(result["file"]?.stringValue ?? "—")")
        if let frame = result["frame"] {
            print("frame: \(numberText(frame["x"])),\(numberText(frame["y"])) "
                  + "\(numberText(frame["width"]))x\(numberText(frame["height"]))")
        }
        print("visible: \(yesNo(result["visible"]?.boolValue))")
        print("passthrough: \(yesNo(result["passthrough"]?.boolValue))")
        print("watching: \(yesNo(result["watching"]?.boolValue))")
        print("opacity: \(numberText(result["opacity"]))")
        print("radius: \(numberText(result["radius"]))")
    }

    private static func printTemplates(_ result: JSONValue) {
        guard let templates = result["templates"]?.arrayValue else {
            printJSON(result)
            return
        }
        for item in templates {
            let name = item["name"]?.stringValue ?? "(untitled)"
            let description = item["description"]?.stringValue ?? ""
            let size = item["size"]
            let dimensions = "\(numberText(size?["width"]))x\(numberText(size?["height"]))"
            let path = item["path"]?.stringValue ?? ""
            let subtitle = description.isEmpty ? "" : "  \(description)"
            print("\(name)\(subtitle)  [\(dimensions)]  \(path)")
        }
    }

    private static func printHumanEvent(_ line: Data) {
        guard let event = try? ControlWire.decodeLine(line, as: ControlEvent.self) else {
            print(String(decoding: line, as: UTF8.self))
            return
        }
        switch event.event {
        case "emit":
            let name = event.name ?? "event"
            let data = event.data.map { ControlWire.jsonText($0) } ?? "null"
            print("[\(name)] \(data)")
        case "loaded":
            print("[loaded] \(event.file ?? event.url ?? "")")
        case "error":
            print("[error] \(event.message ?? "")")
        case "log":
            print("[log] \(event.message ?? "")")
        case "state":
            let name = event.name ?? "state"
            let data = event.data.map { ControlWire.jsonText($0) } ?? "null"
            print("[\(name)] \(data)")
        case "session":
            print("[\(event.name ?? "session")] \(event.session ?? "")")
        default:
            print("[\(event.event)] \(event.message ?? "")")
        }
    }

    private static func numberText(_ value: JSONValue?) -> String {
        guard let number = value?.doubleValue else { return "—" }
        return NumberFormat.text(number, fractionDigits: 2)
    }

    private static func yesNo(_ value: Bool?) -> String {
        guard let value else { return "—" }
        return value ? "on" : "off"
    }

    private static func printJSON(_ value: JSONValue) {
        print(ControlWire.jsonText(value))
    }

    private static func printError(_ message: String) {
        FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    }

    private static func failUsage(_ message: String, json: Bool = false) {
        if json {
            printJSON(.object(["error": .object([
                "code": .string("usage"),
                "message": .string(message)
            ])]))
        } else {
            printError(message)
            FileHandle.standardError.write(Data("run 'PinShell --help' for usage\n".utf8))
        }
    }

    private static func printHelp() {
        let width = CLICommandCatalog.commands
            .map { "PinShell \($0.usage)".count }
            .max() ?? 0
        let usageLines = CLICommandCatalog.commands.map { spec -> String in
            let usage = "PinShell \(spec.usage)"
            let padding = String(repeating: " ", count: width - usage.count)
            return "  \(usage)\(padding)  \(spec.summary)"
        }.joined(separator: "\n")

        print("""
        PinShell — local HTML overlay shell

        Usage:
        \(usageLines)

        Options:
          --size WxH                           Window size (e.g. 240x80)
          --position <anchor|x,y>              bottom-right, top-left, center, ...
          --passthrough on|off                 Click-through mode
          --opacity 0..1                       Window alpha
          --radius px                          Window corner radius
          --watch                              Auto-reload when the file changes
          --wait                               Wait until the page finishes loading
          --json                               Machine-readable output

        HTML metadata (in the file's <head>):
          <title>Subtitle</title>
          <meta name="description" content="Card subtitle">
          <meta name="pinshell:size" content="240x80">
          <meta name="pinshell:position" content="bottom-right">
          <meta name="pinshell:passthrough" content="false">
          <meta name="pinshell:opacity" content="0.9">
          <meta name="pinshell:radius" content="18">
          <meta name="pinshell:order" content="10">

        Agent example:
          PinShell show ./panel.html --watch --json
          PinShell listen --json
          PinShell eval 'document.querySelector("#status").textContent = "received"'
          PinShell emit agent:message '{"text":"next step"}'

        Exit codes: 0 ok, 1 usage, 2 app unavailable, 3 command failed
        """)
    }
}
