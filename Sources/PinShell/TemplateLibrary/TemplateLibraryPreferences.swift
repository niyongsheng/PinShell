import Foundation
import PinShellCore

enum TemplateLibraryPreferences {
    static let defaultCatalogURL = URL(
        string: "https://pinshell.looplooptech.com/library.json")!

    static let catalogURLKey = "PinShell.templateCatalogURL"
    static let catalogEnvironmentKey = "PINSHELL_TEMPLATE_CATALOG_URL"
    /// 通用页添加的附加模板库（不含官方库）；存储规范化后的绝对地址。
    static let customCatalogURLsKey = "PinShell.templateCatalogURLs"

    enum AddCatalogError: Error, Equatable {
        case empty
        case invalid
        case insecure
        case duplicate
    }

    /// 官方源：环境变量 → UserDefaults → 官方默认源。
    static func catalogURL(environment: [String: String] = ProcessInfo.processInfo.environment,
                           defaults: UserDefaults = .standard) -> URL {
        let candidates = [
            environment[catalogEnvironmentKey],
            defaults.string(forKey: catalogURLKey),
        ]
        for raw in candidates.compactMap({ $0 }) {
            guard let url = try? TemplateCatalogURL.normalize(raw).get(),
                  TemplateLibraryValidation.isAllowedCatalogURL(url) else { continue }
            return url
        }
        return defaultCatalogURL
    }

    /// 用户添加的附加模板库；损坏或不合规的条目会被忽略。
    static func customCatalogURLs(defaults: UserDefaults = .standard) -> [URL] {
        let raws = defaults.stringArray(forKey: customCatalogURLsKey) ?? []
        var seen = Set<String>()
        return raws.compactMap { raw in
            guard let url = try? TemplateCatalogURL.normalize(raw).get(),
                  seen.insert(url.absoluteString).inserted else { return nil }
            return url
        }
    }

    /// 官方库 + 用户添加的库，按顺序去重（官方优先）。
    static func allCatalogURLs(environment: [String: String] = ProcessInfo.processInfo.environment,
                               defaults: UserDefaults = .standard) -> [URL] {
        TemplateLibrarySource.configured(environment: environment, defaults: defaults).map(\.url)
    }

    /// 只校验并规范化地址，不写入偏好；添加弹窗先用它做异步冲突检查。
    static func validateCustomCatalogURL(_ raw: String,
                                         defaults: UserDefaults = .standard) throws -> URL {
        let url: URL
        switch TemplateCatalogURL.normalize(raw) {
        case .success(let normalized):
            url = normalized
        case .failure(let failure):
            switch failure {
            case .empty: throw AddCatalogError.empty
            case .invalid: throw AddCatalogError.invalid
            case .insecure: throw AddCatalogError.insecure
            }
        }

        guard !allCatalogURLs(defaults: defaults).contains(where: {
            $0.absoluteString == url.absoluteString
        }) else {
            throw AddCatalogError.duplicate
        }
        return url
    }

    @discardableResult
    static func addCustomCatalogURL(_ raw: String,
                                    defaults: UserDefaults = .standard) throws -> URL {
        let url = try validateCustomCatalogURL(raw, defaults: defaults)
        var raws = defaults.stringArray(forKey: customCatalogURLsKey) ?? []
        raws.append(url.absoluteString)
        defaults.set(raws, forKey: customCatalogURLsKey)
        return url
    }

    static func removeCustomCatalogURL(_ url: URL, defaults: UserDefaults = .standard) {
        var raws = defaults.stringArray(forKey: customCatalogURLsKey) ?? []
        raws.removeAll { $0 == url.absoluteString }
        defaults.set(raws, forKey: customCatalogURLsKey)
    }
}
