import Foundation

/// 模板文件名校验：只允许 PinShell 模板目录内的平铺 `.html` / `.htm` 文件。
/// MCP / CLI 读写模板时用它把路径限制在模板目录，拒绝目录穿越与符号链接逃逸。
public enum TemplateFilePolicy {
    public enum Error: Swift.Error, Equatable, LocalizedError {
        case emptyName
        case invalidName
        case unsupportedExtension
        case outsideDirectory

        public var errorDescription: String? {
            switch self {
            case .emptyName:
                return "Template name is empty"
            case .invalidName:
                return "Template name must be a plain file name (no path separators)"
            case .unsupportedExtension:
                return "Template must be a .html or .htm file"
            case .outsideDirectory:
                return "Template path escapes the templates folder"
            }
        }
    }

    /// 模板扩展名白名单：目录扫描、目录监视与 MCP/CLI 校验共用同一规则。
    public static func isTemplateFile(named name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return ext == "html" || ext == "htm"
    }

    /// 解析模板文件名到目录内的 URL。只接受平铺文件名，不接受绝对路径或子目录。
    public static func resolve(name raw: String, in directory: URL) throws -> URL {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw Error.emptyName }
        guard name != ".", name != "..",
              name == (name as NSString).lastPathComponent,
              !name.contains("/"), !name.contains("\\") else {
            throw Error.invalidName
        }
        guard isTemplateFile(named: name) else { throw Error.unsupportedExtension }

        let base = directory.standardizedFileURL
        let file = base.appendingPathComponent(name)
        guard file.deletingLastPathComponent().standardizedFileURL.path == base.path else {
            throw Error.outsideDirectory
        }
        return file
    }

    /// 解析符号链接后确认文件仍在模板目录内（读取/写入前使用）。
    public static func ensureInside(_ url: URL, directory: URL) throws {
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard resolved.path.hasPrefix(prefix) else { throw Error.outsideDirectory }
    }
}
