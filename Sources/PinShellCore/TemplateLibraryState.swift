import Foundation

public struct InstalledTemplateRecord: Codable, Equatable, Sendable {
    public var version: String
    public var sha256: String
    public var installedAt: Date?
    public var sourceCatalog: String?

    public init(version: String, sha256: String,
                installedAt: Date? = nil, sourceCatalog: String? = nil) {
        self.version = version
        self.sha256 = sha256
        self.installedAt = installedAt
        self.sourceCatalog = sourceCatalog
    }
}

public struct TemplateLibraryState: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var installed: [String: InstalledTemplateRecord]
    public var ignored: [String: String]

    public init(schemaVersion: Int = TemplateLibraryState.currentSchemaVersion,
                installed: [String: InstalledTemplateRecord] = [:],
                ignored: [String: String] = [:]) {
        self.schemaVersion = schemaVersion
        self.installed = installed
        self.ignored = ignored
    }

    public static var empty: TemplateLibraryState { TemplateLibraryState() }

    public func record(for id: String) -> InstalledTemplateRecord? { installed[id] }
    public func ignoredVersion(for id: String) -> String? { ignored[id] }
}

public enum TemplateLibraryStateError: Error, Equatable, CustomStringConvertible {
    case unsupportedSchema(Int)
    case unreadable(String)

    public var description: String {
        switch self {
        case .unsupportedSchema(let version):
            return "unsupported template library state schemaVersion \(version)"
        case .unreadable(let message):
            return "unreadable template library state: \(message)"
        }
    }
}

/// `template-library.json` 的原子读写。
/// 损坏文件会改名为 `*.corrupt-<timestamp>.json` 后从空状态恢复；
/// 未来 schema 保留原文件并报错，避免旧 App 覆盖新状态。
public struct TemplateLibraryStateStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() throws -> TemplateLibraryState {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .empty
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let state = try decoder.decode(TemplateLibraryState.self, from: data)
            guard state.schemaVersion == TemplateLibraryState.currentSchemaVersion else {
                throw TemplateLibraryStateError.unsupportedSchema(state.schemaVersion)
            }
            return state
        } catch let error as TemplateLibraryStateError {
            throw error
        } catch {
            try quarantineCorruptFile()
            return .empty
        }
    }

    public func save(_ state: TemplateLibraryState) throws {
        var state = state
        state.schemaVersion = TemplateLibraryState.currentSchemaVersion
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let existed = FileManager.default.fileExists(atPath: url.path)
        try data.write(to: url, options: .atomic)
        if !existed {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        }
    }

    private func quarantineCorruptFile() throws {
        let directory = url.deletingLastPathComponent()
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let name = url.deletingPathExtension().lastPathComponent
        let backup = directory.appendingPathComponent("\(name).corrupt-\(timestamp).json")
        do {
            try FileManager.default.moveItem(at: url, to: backup)
        } catch {
            throw TemplateLibraryStateError.unreadable(error.localizedDescription)
        }
    }
}
