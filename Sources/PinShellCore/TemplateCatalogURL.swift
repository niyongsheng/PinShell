import Foundation

/// 用户输入的模板库地址规范化：补全 scheme 与 `/library.json`，
/// 并限制为 HTTPS（本地开发允许 loopback HTTP）。
public enum TemplateCatalogURL {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case empty
        case invalid
        case insecure

        public var description: String {
            switch self {
            case .empty:
                return "empty template catalog URL"
            case .invalid:
                return "invalid template catalog URL"
            case .insecure:
                return "unsupported template catalog URL scheme"
            }
        }
    }

    /// 站点根地址、带 `/` 的目录地址会补成 `library.json`；
    /// 完整文件地址保持不变。query / fragment / userinfo 一律拒绝，
    /// 避免缓存与深链信任出现歧义。
    public static func normalize(_ raw: String) -> Result<URL, Failure> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              let host = components.host, !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            return .failure(.invalid)
        }
        components.scheme = scheme
        components.host = host.lowercased()
        guard scheme == "https"
            || (scheme == "http" && TemplateLibraryValidation.isLoopbackHost(host)) else {
            return .failure(.insecure)
        }

        let path = components.percentEncodedPath
        if path.isEmpty || path == "/" {
            components.percentEncodedPath = "/library.json"
        } else if path.hasSuffix("/") {
            components.percentEncodedPath = path + "library.json"
        }

        guard let url = components.url,
              TemplateLibraryValidation.isAllowedCatalogURL(url) else {
            return .failure(.invalid)
        }
        return .success(url)
    }
}
