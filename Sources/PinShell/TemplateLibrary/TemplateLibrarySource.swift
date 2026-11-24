import Foundation

/// 一个模板库来源。官方库始终排在最前，用户添加的附加库依次排列。
struct TemplateLibrarySource: Equatable, Sendable, Identifiable {
    let url: URL
    let isOfficial: Bool

    var id: String { url.absoluteString }

    /// 来源标题：官方库用本地化名称；附加库用 host[+路径目录]。
    var displayName: String {
        guard let host = url.host, !host.isEmpty else { return url.absoluteString }
        let port = url.port.map { ":\($0)" } ?? ""
        let directory = url.deletingLastPathComponent().path
        guard directory != "/", directory != "." else { return host + port }
        return host + port + directory
    }

    /// 界面展示名：官方来源使用本地化名称，其余沿用 host 标题。
    var localizedTitle: String {
        isOfficial
            ? NSLocalizedString("console.general.library.official", comment: "")
            : displayName
    }

    static func configured(environment: [String: String] = ProcessInfo.processInfo.environment,
                           defaults: UserDefaults = .standard) -> [TemplateLibrarySource] {
        let officialURL = TemplateLibraryPreferences.catalogURL(
            environment: environment, defaults: defaults)
        var sources = [TemplateLibrarySource(url: officialURL, isOfficial: true)]
        var seen = Set([officialURL.absoluteString])
        for url in TemplateLibraryPreferences.customCatalogURLs(defaults: defaults)
            where seen.insert(url.absoluteString).inserted {
            sources.append(TemplateLibrarySource(url: url, isOfficial: false))
        }
        return sources
    }
}
