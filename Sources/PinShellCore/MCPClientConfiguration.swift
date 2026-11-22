import Foundation

// MARK: - 客户端

/// PinShell 支持自动写入 MCP 配置的客户端。
///
/// 只依赖各客户端公开的配置文件：
/// - Claude Code: `~/.claude.json` 顶层 `mcpServers`（user scope）
/// - Codex: `~/.codex/config.toml` 的 `[mcp_servers.pinshell]`
/// - Cursor: `~/.cursor/mcp.json`
/// - Pi: `~/.pi/agent/mcp.json`
public enum MCPClient: String, CaseIterable, Sendable {
    case claudeCode
    case codex
    case cursor
    case pi

    /// 写入配置时使用的服务名。
    public static let serverName = "pinshell"

    /// 当前可执行文件的 stdio 服务条目：安装、帮助与控制台展示共用同一份。
    public static func serverEntry(executable: URL) -> [String: Any] {
        ["command": executable.path, "args": ["mcp"]]
    }

    /// 标准 MCP 客户端配置对象。
    public static func serverConfiguration(executable: URL) -> [String: Any] {
        ["mcpServers": [serverName: serverEntry(executable: executable)]]
    }

    /// 格式化后的配置文本；帮助信息用紧凑模式，控制台用 pretty。
    public static func serverConfigurationJSON(executable: URL, pretty: Bool = true) -> String {
        let options: JSONSerialization.WritingOptions = pretty
            ? [.prettyPrinted, .sortedKeys]
            : [.sortedKeys]
        let object = serverConfiguration(executable: executable)
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: options) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }

    public var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        case .pi: return "Pi"
        }
    }

    /// 配置文件位置；支持各客户端自己的环境变量覆盖。
    public func configURL(in context: MCPClientContext = .current) -> URL {
        switch self {
        case .claudeCode:
            let directory = context.environment["CLAUDE_CONFIG_DIR"]
                .flatMap { $0.isEmpty ? nil : context.expand($0) }
                ?? context.home
            return directory.appendingPathComponent(".claude.json")

        case .codex:
            let directory = context.environment["CODEX_HOME"]
                .flatMap { $0.isEmpty ? nil : context.expand($0) }
                ?? context.home.appendingPathComponent(".codex", isDirectory: true)
            return directory.appendingPathComponent("config.toml")

        case .cursor:
            return context.home
                .appendingPathComponent(".cursor", isDirectory: true)
                .appendingPathComponent("mcp.json")

        case .pi:
            let directory = context.environment["PI_CODING_AGENT_DIR"]
                .flatMap { $0.isEmpty ? nil : context.expand($0) }
                ?? context.home
                    .appendingPathComponent(".pi", isDirectory: true)
                    .appendingPathComponent("agent", isDirectory: true)
            return directory.appendingPathComponent("mcp.json")
        }
    }

    /// 是否检测到该客户端（配置文件/配置目录/可执行文件任一存在）。
    public func isDetected(in context: MCPClientContext = .current) -> Bool {
        let manager = context.fileManager
        switch self {
        case .claudeCode:
            return manager.fileExists(atPath: configURL(in: context).path)
                || manager.fileExists(atPath: context.home
                    .appendingPathComponent(".claude", isDirectory: true).path)
                || context.findExecutable("claude")

        case .codex:
            return manager.fileExists(atPath: configURL(in: context).path)
                || manager.fileExists(atPath: configURL(in: context)
                    .deletingLastPathComponent().path)
                || context.findExecutable("codex")

        case .cursor:
            return manager.fileExists(atPath: configURL(in: context)
                    .deletingLastPathComponent().path)
                || manager.fileExists(atPath: "/Applications/Cursor.app")
                || manager.fileExists(atPath: context.home
                    .appendingPathComponent("Applications/Cursor.app").path)
                || context.findExecutable("cursor-agent")

        case .pi:
            return manager.fileExists(atPath: configURL(in: context).path)
                || manager.fileExists(atPath: configURL(in: context)
                    .deletingLastPathComponent().path)
                || manager.fileExists(atPath: context.home
                    .appendingPathComponent(".pi", isDirectory: true).path)
                || context.findExecutable("pi")
        }
    }

    /// 读取当前配置状态；配置文件损坏时不抛错，按“未配置”处理。
    public func status(executable: URL,
                       in context: MCPClientContext = .current) -> MCPClientStatus {
        let url = configURL(in: context)
        let configuredCommand: String?
        switch self {
        case .codex:
            configuredCommand = Self.codexCommand(
                in: (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            )
        default:
            configuredCommand = Self.jsonCommand(at: url, fileManager: context.fileManager)
        }

        let configured = configuredCommand != nil
        let matches = configuredCommand.map {
            Self.samePath($0, executable.path, home: context.home)
        } ?? false
        return MCPClientStatus(detected: isDetected(in: context),
                               configured: configured,
                               commandMatches: matches,
                               configPath: url.path)
    }

    /// 写入或更新 PinShell 的 stdio 服务配置。
    public func install(executable: URL,
                        in context: MCPClientContext = .current) throws {
        let url = configURL(in: context)
        switch self {
        case .codex:
            try installTOML(at: url, executable: executable, context: context)
        default:
            try installJSON(at: url, executable: executable, context: context)
        }
    }

    /// 移除 PinShell 的服务配置；其他服务与配置内容保持不变。
    public func uninstall(in context: MCPClientContext = .current) throws {
        let url = configURL(in: context)
        switch self {
        case .codex:
            try uninstallTOML(at: url, context: context)
        default:
            try uninstallJSON(at: url, context: context)
        }
    }

    // MARK: JSON

    private func installJSON(at url: URL, executable: URL,
                             context: MCPClientContext) throws {
        let url = Self.resolvedWriteURL(url, context: context)
        var root = try Self.loadJSONObject(at: url, fileManager: context.fileManager) ?? [:]

        var servers: [String: Any]
        if let existing = root["mcpServers"] {
            guard let dictionary = existing as? [String: Any] else {
                throw MCPClientConfigError.invalidStructure(url)
            }
            servers = dictionary
        } else {
            servers = [:]
        }

        // 已经指向当前可执行文件时不再重写，避免无谓地改动大配置文件
        if let existing = servers[Self.serverName] as? [String: Any],
           existing["command"] as? String == executable.path,
           existing["args"] as? [String] == ["mcp"] {
            return
        }

        servers[Self.serverName] = Self.serverEntry(executable: executable)
        root["mcpServers"] = servers
        try Self.writeJSONObject(root, to: url, context: context)
    }

    private func uninstallJSON(at url: URL, context: MCPClientContext) throws {
        let url = Self.resolvedWriteURL(url, context: context)
        guard context.fileManager.fileExists(atPath: url.path),
              var root = try Self.loadJSONObject(at: url, fileManager: context.fileManager),
              var servers = root["mcpServers"] as? [String: Any],
              servers.removeValue(forKey: Self.serverName) != nil else {
            return
        }
        root["mcpServers"] = servers
        try Self.writeJSONObject(root, to: url, context: context)
    }

    private static func loadJSONObject(at url: URL,
                                       fileManager: FileManager) throws -> [String: Any]? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let isBlank = data.allSatisfy { byte in
            byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
        }
        guard !isBlank else { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            throw MCPClientConfigError.invalidJSON(url)
        }
        guard let dictionary = object as? [String: Any] else {
            throw MCPClientConfigError.invalidJSON(url)
        }
        return dictionary
    }

    private static func writeJSONObject(_ object: [String: Any], to url: URL,
                                        context: MCPClientContext) throws {
        let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys]
        let data = try JSONSerialization.data(withJSONObject: object, options: options)
        try writeAtomically(data, to: url, context: context)
    }

    private static func jsonCommand(at url: URL, fileManager: FileManager) -> String? {
        guard let root = try? loadJSONObject(at: url, fileManager: fileManager),
              let servers = root["mcpServers"] as? [String: Any],
              let entry = servers[serverName] as? [String: Any],
              let command = entry["command"] as? String,
              !command.isEmpty else {
            return nil
        }
        return command
    }

    // MARK: TOML

    private func installTOML(at url: URL, executable: URL,
                             context: MCPClientContext) throws {
        let url = Self.resolvedWriteURL(url, context: context)
        let text = try Self.readText(at: url, context: context)
        let body = [
            "command = \(Self.tomlString(executable.path))",
            "args = [\"mcp\"]"
        ]
        let updated = Self.upsertTable(named: "mcp_servers.\(Self.serverName)",
                                       body: body, in: text)
        try Self.writeText(updated, to: url, context: context)
    }

    private func uninstallTOML(at url: URL, context: MCPClientContext) throws {
        let url = Self.resolvedWriteURL(url, context: context)
        guard context.fileManager.fileExists(atPath: url.path) else { return }
        let text = try Self.readText(at: url, context: context)
        let updated = Self.removeTable(named: "mcp_servers.\(Self.serverName)", from: text)
        guard updated != text else { return }
        try Self.writeText(updated, to: url, context: context)
    }

    private static func readText(at url: URL, context: MCPClientContext) throws -> String {
        guard context.fileManager.fileExists(atPath: url.path) else { return "" }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw MCPClientConfigError.unreadable(url)
        }
        return text
    }

    private static func writeText(_ text: String, to url: URL,
                                  context: MCPClientContext) throws {
        try writeAtomically(Data(text.utf8), to: url, context: context)
    }

    /// 原子写入配置文件：建目录、保留已有权限（新文件 0600）。
    private static func writeAtomically(_ data: Data, to url: URL,
                                        context: MCPClientContext) throws {
        try context.createConfigDirectory(for: url)
        let previousPermissions = (try? context.fileManager
            .attributesOfItem(atPath: url.path))?[.posixPermissions]
        try data.write(to: url, options: .atomic)
        try? context.fileManager.setAttributes(
            [.posixPermissions: previousPermissions ?? 0o600],
            ofItemAtPath: url.path)
    }

    private static func codexCommand(in text: String) -> String? {
        let target = normalizeTableName("mcp_servers.\(serverName)")
        var inSection = false
        for line in text.components(separatedBy: "\n") {
            if let name = tableName(line) {
                inSection = name == target
                continue
            }
            guard inSection else { continue }
            guard let value = stringValue(forKey: "command", in: line) else { continue }
            return value
        }
        return nil
    }

    // MARK: TOML 编辑

    /// 表头行（`[a.b]` / `[[a.b]]`，允许行尾注释）返回规范化表名，其他行返回 nil。
    static func tableName(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("[") else { return nil }

        let inner: Substring
        let remainder: Substring
        if trimmed.hasPrefix("[[") {
            guard let close = trimmed.range(of: "]]") else { return nil }
            inner = trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<close.lowerBound]
            remainder = trimmed[close.upperBound...]
        } else {
            guard let close = trimmed.firstIndex(of: "]") else { return nil }
            inner = trimmed[trimmed.index(after: trimmed.startIndex)..<close]
            remainder = trimmed[trimmed.index(after: close)...]
        }

        // 排除多行数组的续行（如 "[1, 2]"）：表名不含 = , { }
        guard inner.rangeOfCharacter(from: CharacterSet(charactersIn: "=,{}")) == nil else {
            return nil
        }
        // 表头之后只允许空白或注释
        let trailer = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trailer.isEmpty || trailer.hasPrefix("#") else { return nil }

        let normalized = normalizeTableName(String(inner))
        return normalized.isEmpty ? nil : normalized
    }

    static func normalizeTableName(_ name: String) -> String {
        name.filter { !$0.isWhitespace && $0 != "\"" && $0 != "'" }
    }

    static func upsertTable(named name: String, body: [String], in text: String) -> String {
        var lines = trimmingTrailingBlankLines(removeTableLines(named: name, from: text))
        if !lines.isEmpty { lines.append("") }
        lines.append("[\(name)]")
        lines.append(contentsOf: body)
        lines.append("")
        return lines.joined(separator: "\n")
    }

    static func removeTable(named name: String, from text: String) -> String {
        let lines = trimmingTrailingBlankLines(removeTableLines(named: name, from: text))
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }

    private static func trimmingTrailingBlankLines(_ lines: [String]) -> [String] {
        var result = lines
        while let last = result.last,
              last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.removeLast()
        }
        return result
    }


    /// 删除目标表及其子表（如 `[mcp_servers.pinshell.env]`）。
    private static func removeTableLines(named name: String, from text: String) -> [String] {
        var lines = text.components(separatedBy: "\n")
        let target = normalizeTableName(name)
        var index = 0
        while index < lines.count {
            guard let current = tableName(lines[index]) else {
                index += 1
                continue
            }
            guard current == target || current.hasPrefix(target + ".") else {
                index += 1
                continue
            }
            var end = index + 1
            while end < lines.count, tableName(lines[end]) == nil {
                end += 1
            }
            lines.removeSubrange(index..<end)
        }
        return lines
    }

    private static func stringValue(forKey key: String, in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(key), let equals = trimmed.firstIndex(of: "=") else {
            return nil
        }
        let name = trimmed[..<equals].trimmingCharacters(in: .whitespacesAndNewlines)
        guard name == key else { return nil }
        let raw = trimmed[trimmed.index(after: equals)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return parseTOMLString(raw)
    }

    private static func parseTOMLString(_ raw: String) -> String? {
        guard let quote = raw.first, quote == "\"" || quote == "'" else { return nil }
        var result = ""
        var iterator = raw.dropFirst().makeIterator()
        var escaped = false
        while let character = iterator.next() {
            if quote == "'" {
                if character == "'" { return result }
                result.append(character)
                continue
            }
            if escaped {
                switch character {
                case "n": result.append("\n")
                case "t": result.append("\t")
                case "r": result.append("\r")
                case "\\": result.append("\\")
                case "\"": result.append("\"")
                default: result.append(character)
                }
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                return result
            } else {
                result.append(character)
            }
        }
        return nil
    }

    private static func tomlString(_ value: String) -> String {
        var result = "\""
        for character in value {
            switch character {
            case "\\": result += "\\\\"
            case "\"": result += "\\\""
            case "\n": result += "\\n"
            case "\t": result += "\\t"
            case "\r": result += "\\r"
            default: result.append(character)
            }
        }
        return result + "\""
    }

    // MARK: 路径

    /// 配置文件是符号链接时写入真实目标，避免原子写覆盖链接本身（dotfiles 场景）。
    private static func resolvedWriteURL(_ url: URL,
                                         context: MCPClientContext) -> URL {
        guard let attributes = try? context.fileManager.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeSymbolicLink else {
            return url
        }
        return url.resolvingSymlinksInPath()
    }

    private static func samePath(_ lhs: String, _ rhs: String, home: URL) -> Bool {
        func normalized(_ path: String) -> String {
            let expanded: String
            if path == "~" {
                expanded = home.path
            } else if path.hasPrefix("~/") {
                expanded = home.appendingPathComponent(String(path.dropFirst(2))).path
            } else {
                expanded = path
            }
            return URL(fileURLWithPath: expanded)
                .standardizedFileURL
                .resolvingSymlinksInPath()
                .path
        }
        return normalized(lhs) == normalized(rhs)
    }
}

// MARK: - 状态

public struct MCPClientStatus: Equatable, Sendable {
    public let detected: Bool
    public let configured: Bool
    public let commandMatches: Bool
    public let configPath: String

    public init(detected: Bool, configured: Bool,
                commandMatches: Bool, configPath: String) {
        self.detected = detected
        self.configured = configured
        self.commandMatches = commandMatches
        self.configPath = configPath
    }

    /// 已配置，但写入的命令不是当前 App 的可执行文件（如 App 被移动过）。
    public var needsUpdate: Bool { configured && !commandMatches }
}

// MARK: - 环境

/// 注入 home / 环境变量 / 文件系统，便于测试客户端配置逻辑。
public struct MCPClientContext {
    public var home: URL
    public var environment: [String: String]
    public var fileManager: FileManager
    public var executableSearchPaths: [String]

    public init(home: URL,
                environment: [String: String] = [:],
                fileManager: FileManager = .default,
                executableSearchPaths: [String] = []) {
        self.home = home
        self.environment = environment
        self.fileManager = fileManager
        self.executableSearchPaths = executableSearchPaths
    }

    /// 当前用户环境。GUI App 从 Finder 启动时 PATH 很短，补上常见安装目录。
    public static var current: MCPClientContext {
        let environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser
        var paths = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        paths += [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            home.appendingPathComponent(".local/bin").path,
            home.appendingPathComponent(".bun/bin").path,
            home.appendingPathComponent(".npm-global/bin").path,
            home.appendingPathComponent("Library/pnpm").path,
        ]
        var seen = Set<String>()
        paths = paths.filter { seen.insert($0).inserted }
        return MCPClientContext(home: home,
                                environment: environment,
                                fileManager: .default,
                                executableSearchPaths: paths)
    }

    func expand(_ path: String) -> URL {
        if path == "~" { return home }
        if path.hasPrefix("~/") {
            return home.appendingPathComponent(String(path.dropFirst(2)))
        }
        return URL(fileURLWithPath: path)
    }

    func findExecutable(_ name: String) -> Bool {
        executableSearchPaths.contains {
            fileManager.isExecutableFile(atPath:
                URL(fileURLWithPath: $0).appendingPathComponent(name).path)
        }
    }

    func createConfigDirectory(for url: URL) throws {
        let directory = url.deletingLastPathComponent()
        guard !fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.createDirectory(at: directory,
                                        withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
    }
}

// MARK: - 错误

public enum MCPClientConfigError: Error, LocalizedError, Equatable {
    case invalidJSON(URL)
    case invalidStructure(URL)
    case unreadable(URL)

    public var errorDescription: String? {
        switch self {
        case .invalidJSON(let url):
            return "Not a valid JSON file: \(url.path)"
        case .invalidStructure(let url):
            return "Unexpected mcpServers format: \(url.path)"
        case .unreadable(let url):
            return "Cannot read config file: \(url.path)"
        }
    }
}
