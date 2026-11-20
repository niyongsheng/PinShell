import Foundation

/// 模板文件的统一读写入口：路径限制、大小上限、权限策略只在这里定义。
public enum TemplateStorage {
    /// 单文件上限：防止失控 agent / 页面耗尽内存。
    public static let maxBytes = 512 * 1024

    public enum Error: Swift.Error, Equatable, LocalizedError {
        case notFound(String)
        case tooLarge(Int)

        public var errorDescription: String? {
            switch self {
            case .notFound(let name):
                return "Template not found: \(name)"
            case .tooLarge(let bytes):
                return "Template exceeds \(TemplateStorage.maxBytes) bytes (got \(bytes))"
            }
        }
    }

    /// 解析模板目录内的平铺文件名，并确认符号链接没有逃出目录。
    public static func resolve(name: String, in directory: URL) throws -> URL {
        let url = try TemplateFilePolicy.resolve(name: name, in: directory)
        try TemplateFilePolicy.ensureInside(url, directory: directory)
        return url
    }

    public static func read(name: String, in directory: URL) throws -> (url: URL, content: String) {
        let url = try resolve(name: name, in: directory)
        return (url, try read(at: url))
    }

    public static func read(at url: URL) throws -> String {
        guard isRegularFile(url) else { throw Error.notFound(url.lastPathComponent) }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path))
            .flatMap { ($0[.size] as? NSNumber)?.intValue } ?? 0
        guard size <= maxBytes else { throw Error.tooLarge(size) }
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return content
    }

    @discardableResult
    public static func write(name: String, html: String, in directory: URL) throws -> URL {
        let url = try resolve(name: name, in: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try write(html, to: url)
        return url
    }

    /// 原子写入；保留已有文件权限，新文件默认 0600。
    public static func write(_ html: String, to url: URL) throws {
        let bytes = html.utf8.count
        guard bytes <= maxBytes else { throw Error.tooLarge(bytes) }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        try Data(html.utf8).write(to: url, options: .atomic)
        let permissions = attributes?[.posixPermissions] ?? 0o600
        try? FileManager.default.setAttributes([.posixPermissions: permissions],
                                               ofItemAtPath: url.path)
    }

    @discardableResult
    public static func delete(name: String, in directory: URL) throws -> URL {
        let url = try resolve(name: name, in: directory)
        guard isRegularFile(url) else { throw Error.notFound(url.lastPathComponent) }
        try FileManager.default.removeItem(at: url)
        return url
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }
}
