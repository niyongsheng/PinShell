import Foundation
#if canImport(CoreFoundation)
import CoreFoundation
#endif
#if canImport(Darwin)
import Darwin
#endif

// MARK: - JSONValue

/// 轻量 JSON 值，避免为控制协议定义大量强类型 DTO。
public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container,
                                                   debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    /// 从 WKScriptMessage.body / JSONSerialization 的任意值构造。
    public init(any value: Any) {
        switch value {
        case is NSNull:
            self = .null
        case let value as NSNumber:
            // NSNumber(1) 也能 as? Bool；必须先按 CFBoolean 类型区分，否则数字 1 会变成 true
            #if canImport(CoreFoundation)
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else {
                self = .number(value.doubleValue)
            }
            #else
            self = .number(value.doubleValue)
            #endif
        case let value as Bool:
            self = .bool(value)
        case let value as Int:
            self = .number(Double(value))
        case let value as Double:
            self = .number(value)
        case let value as String:
            self = .string(value)
        case let value as [Any]:
            self = .array(value.map(JSONValue.init(any:)))
        case let value as [String: Any]:
            self = .object(value.mapValues(JSONValue.init(any:)))
        default:
            self = .null
        }
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var doubleValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    public var intValue: Int? {
        guard case .number(let value) = self, value.isFinite else { return nil }
        return Int(value)
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }

    /// 转回 JSONSerialization / evaluateJavaScript 可用的 Foundation 值。
    public var anyValue: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let value): return value
        case .number(let value): return value
        case .string(let value): return value
        case .array(let value): return value.map(\.anyValue)
        case .object(let value): return value.mapValues(\.anyValue)
        }
    }

    /// RFC 7386 JSON Merge Patch：对象递归合并，null 删除键，其余类型整体替换。
    /// 面板共享状态和 `state:delta` 事件共用这套语义（JS 侧实现必须保持一致）。
    public func applyingMergePatch(_ patch: JSONValue) -> JSONValue {
        guard case .object(let patchObject) = patch else { return patch }
        var base: [String: JSONValue]
        if case .object(let current) = self {
            base = current
        } else {
            base = [:]
        }
        for (key, value) in patchObject {
            if case .null = value {
                base.removeValue(forKey: key)
            } else {
                let current = base[key] ?? .null
                base[key] = current.applyingMergePatch(value)
            }
        }
        return .object(base)
    }
}

// MARK: - Messages

public struct ControlRequest: Codable, Equatable, Sendable {
    public var id: String
    public var cmd: String
    public var args: [String: JSONValue]

    public init(id: String = UUID().uuidString,
                cmd: String,
                args: [String: JSONValue] = [:]) {
        self.id = id
        self.cmd = cmd
        self.args = args
    }
}

public struct ControlError: Codable, Equatable, Sendable {
    public var code: String
    public var message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public struct ControlResponse: Codable, Equatable, Sendable {
    public var id: String
    public var ok: Bool
    public var result: JSONValue?
    public var error: ControlError?

    public init(id: String, ok: Bool, result: JSONValue? = nil, error: ControlError? = nil) {
        self.id = id
        self.ok = ok
        self.result = result
        self.error = error
    }

    public static func success(id: String, result: JSONValue? = .object([:])) -> ControlResponse {
        ControlResponse(id: id, ok: true, result: result)
    }

    public static func failure(id: String, code: String, message: String) -> ControlResponse {
        ControlResponse(id: id, ok: false, error: ControlError(code: code, message: message))
    }
}

/// 应用主动推送的事件（listen 订阅）。
///
/// 事件在经过 `EventLog` 时补上 `seq` / `epoch` / `ts`，`session` 由窗口控制器补上。
/// `type` 是事件的命名空间（`ui`、`state`、`lifecycle`、`log`，或页面自定义的
/// `pet`、`system`、`todo` 等），供 `pinshell_poll_events` / `pinshell_await_event`
/// 做过滤。`event` 保留来源类型（`emit`、`loaded`、`error`、`log`、`state`、`session`）。
public struct ControlEvent: Codable, Equatable, Sendable {
    public var event: String
    public var name: String?
    public var data: JSONValue?
    public var message: String?
    public var file: String?
    public var url: String?
    public var seq: Int?
    public var epoch: String?
    public var session: String?
    public var type: String?
    public var ts: Double?

    public init(event: String,
                name: String? = nil,
                data: JSONValue? = nil,
                message: String? = nil,
                file: String? = nil,
                url: String? = nil,
                seq: Int? = nil,
                epoch: String? = nil,
                session: String? = nil,
                type: String? = nil,
                ts: Double? = nil) {
        self.event = event
        self.name = name
        self.data = data
        self.message = message
        self.file = file
        self.url = url
        self.seq = seq
        self.epoch = epoch
        self.session = session
        self.type = type
        self.ts = ts
    }

    /// 页面 emit 的事件。没有命名空间（`name:event`）的名称归类为 `ui`。
    public static func emit(name: String, data: JSONValue) -> ControlEvent {
        ControlEvent(event: "emit", name: name, data: data, type: category(for: name))
    }

    public static func loaded(file: String, url: String) -> ControlEvent {
        ControlEvent(event: "loaded", name: "lifecycle:loaded", file: file, url: url,
                     type: "lifecycle")
    }

    public static func error(_ message: String) -> ControlEvent {
        ControlEvent(event: "error", name: "lifecycle:error", message: message,
                     type: "lifecycle")
    }

    public static func log(_ message: String) -> ControlEvent {
        ControlEvent(event: "log", name: "log", message: message, type: "log")
    }

    public static func stateSnapshot(_ state: JSONValue) -> ControlEvent {
        ControlEvent(event: "state", name: "state:snapshot",
                     data: .object(["state": state]), type: "state")
    }

    /// 只带补丁，不带完整 state：避免重复数据和事件行过大；快照用 pinshell_state 读。
    public static func stateDelta(_ patch: JSONValue) -> ControlEvent {
        ControlEvent(event: "state", name: "state:delta",
                     data: .object(["patch": patch]), type: "state")
    }

    public static func sessionStarted(previous: String?) -> ControlEvent {
        ControlEvent(event: "session", name: "session:started",
                     data: .object(["previous": previous.map(JSONValue.string) ?? .null]),
                     type: "lifecycle")
    }

    public static func sessionEnded() -> ControlEvent {
        ControlEvent(event: "session", name: "session:ended", type: "lifecycle")
    }

    /// `todo-list:changed` → `todo-list`，`submit` → `ui`。
    public static func category(for name: String) -> String {
        guard let colon = name.firstIndex(of: ":") else { return "ui" }
        let prefix = String(name[..<colon])
        return prefix.isEmpty ? "ui" : prefix
    }

    public var jsonValue: JSONValue {
        guard let data = try? ControlWire.encoder.encode(self),
              let object = try? JSONSerialization.jsonObject(with: data,
                                                             options: [.fragmentsAllowed]) else {
            return .null
        }
        return JSONValue(any: object)
    }
}

// MARK: - Framing

public enum LineFramerError: Error, Equatable {
    case oversizedLine(maxBytes: Int)
}

/// 行分隔 JSON 的增量分帧器（不依赖换行外的任何分隔符）。
public struct LineFramer {
    public let maxLineBytes: Int
    private var buffer = Data()

    public init(maxLineBytes: Int = ControlProtocolConstants.maxLineBytes) {
        self.maxLineBytes = maxLineBytes
    }

    public mutating func append(_ chunk: Data) throws -> [Data] {
        buffer.append(chunk)
        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[buffer.startIndex..<newline])
            buffer.removeSubrange(buffer.startIndex...newline)
            if line.count > maxLineBytes {
                throw LineFramerError.oversizedLine(maxBytes: maxLineBytes)
            }
            if !line.isEmpty {
                lines.append(line)
            }
        }
        if buffer.count > maxLineBytes {
            throw LineFramerError.oversizedLine(maxBytes: maxLineBytes)
        }
        return lines
    }
}

public enum ControlProtocolConstants {
    /// 单条消息上限：防止失控页面/客户端耗尽内存。
    public static let maxLineBytes = 1 << 20
}

public enum ControlWire {
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    public static let decoder = JSONDecoder()

    public static func encodeLine<T: Encodable>(_ value: T) throws -> Data {
        var data = try encoder.encode(value)
        data.append(0x0A)
        return data
    }

    public static func decodeLine<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
        try decoder.decode(type, from: data)
    }

    /// 单行 JSON 文本（CLI / MCP 输出共用）。
    public static func jsonText<T: Encodable>(_ value: T) -> String {
        guard let data = try? encoder.encode(value) else { return "null" }
        return String(decoding: data, as: UTF8.self)
    }

    public static func jsonText(_ value: JSONValue) -> String {
        guard let data = try? encoder.encode(value) else { return "null" }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Endpoint

public enum ControlEndpoint {
    /// ~/Library/Application Support/PinShell
    ///
    /// `PINSHELL_HOME` 可覆盖整个数据目录，用于测试或多实例隔离。
    public static func applicationDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["PINSHELL_HOME"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath,
                       isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("PinShell", isDirectory: true)
    }

    /// Unix socket 路径；路径过长（sun_path 上限 104）时退回临时目录。
    public static func socketURL() -> URL {
        let preferred = applicationDirectory().appendingPathComponent("control.sock")
        if preferred.path.utf8.count < 100 {
            return preferred
        }
        #if canImport(Darwin)
        let uid = getuid()
        #else
        let uid = 0
        #endif
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pinshell-\(uid).sock")
    }

    /// 兼容旧路径命名（测试/诊断用）。
    public static func socketPath() -> String {
        socketURL().path
    }
}
