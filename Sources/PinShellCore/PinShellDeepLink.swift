import Foundation

/// 官网“安装到 PinShell”深链：`pinshell://install?template=<id>&catalog=<url>`。
///
/// 安全约束：
/// - `catalog` 必须与 App 当前配置的模板库地址完全一致（scheme/host/port/path），
///   防止任意域名借深链触发安装；
/// - `template` 只允许小写字母、数字和连字符，实际安装内容始终从受信任的 catalog 读取，
///   深链不携带可执行文件或任意下载地址。
public enum PinShellDeepLink {
    public struct InstallRequest: Equatable, Sendable {
        public let templateID: String

        public init(templateID: String) {
            self.templateID = templateID
        }
    }

    public static let scheme = "pinshell"
    private static let installHost = "install"

    /// 官网“安装到 PinShell”按钮使用的深链；与 `installRequest(from:trustedCatalogURL:)` 成对维护。
    public static func installURL(templateID: String, catalogURL: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = installHost
        components.queryItems = [
            URLQueryItem(name: "template", value: templateID),
            URLQueryItem(name: "catalog", value: catalogURL),
        ]
        return components.url
    }

    public static func installRequest(from url: URL,
                                      trustedCatalogURL: URL) -> InstallRequest? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == scheme,
              components.host?.lowercased() == installHost,
              components.user == nil,
              components.password == nil,
              let items = components.queryItems else {
            return nil
        }

        let templateValues = items.filter { $0.name == "template" }.compactMap(\.value)
        let catalogValues = items.filter { $0.name == "catalog" }.compactMap(\.value)
        guard templateValues.count == 1,
              catalogValues.count == 1,
              TemplateLibraryValidation.isValidID(templateValues[0]),
              templateValues[0].count <= 64,
              let catalogURL = URL(string: catalogValues[0]),
              TemplateLibraryValidation.isAllowedCatalogURL(catalogURL),
              let expected = canonicalCatalogURL(trustedCatalogURL),
              let actual = canonicalCatalogURL(catalogURL),
              expected == actual else {
            return nil
        }

        return InstallRequest(templateID: templateValues[0])
    }

    // MARK: - 校验

    /// 规范化 catalog 地址；带 userinfo / query / fragment 的一律拒绝。
    private static func canonicalCatalogURL(_ url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            return nil
        }
        let port = components.port.map { ":\($0)" } ?? ""
        let path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        return "\(scheme)://\(host)\(port)\(path)"
    }
}
