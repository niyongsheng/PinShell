import Foundation
import PinShellCore

enum TemplateLibraryPreferences {
    static let defaultCatalogURL = URL(
        string: "https://pinshell.looplooptech.com/library.json")!

    static let catalogURLKey = "PinShell.templateCatalogURL"
    static let catalogEnvironmentKey = "PINSHELL_TEMPLATE_CATALOG_URL"

    /// 环境变量 → UserDefaults → 官方默认源。
    static func catalogURL(environment: [String: String] = ProcessInfo.processInfo.environment,
                           defaults: UserDefaults = .standard) -> URL {
        let candidates = [
            environment[catalogEnvironmentKey],
            defaults.string(forKey: catalogURLKey),
        ]
        for raw in candidates.compactMap({ $0 }) {
            guard let url = URL(string: raw),
                  TemplateLibraryValidation.isAllowedCatalogURL(url) else { continue }
            return url
        }
        return defaultCatalogURL
    }
}
