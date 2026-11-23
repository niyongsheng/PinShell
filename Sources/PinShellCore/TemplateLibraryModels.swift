import Foundation

/// 官网 `library.json` 的 Codable 模型。
/// 所有非必要字段都允许缺失，新增字段向后兼容；严格校验由
/// `TemplateLibraryValidation` 完成。
public struct TemplateLibraryIndex: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var generatedAt: String?
    public var categories: [TemplateLibraryCategory]?
    public var templates: [TemplateLibraryEntry]

    public init(schemaVersion: Int = 1,
                generatedAt: String? = nil,
                categories: [TemplateLibraryCategory]? = nil,
                templates: [TemplateLibraryEntry] = []) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.categories = categories
        self.templates = templates
    }

    public var categoryList: [TemplateLibraryCategory] { categories ?? [] }

    public func template(id: String) -> TemplateLibraryEntry? {
        templates.first { $0.id == id }
    }
}

public struct TemplateLibraryCategory: Codable, Equatable, Sendable {
    public var id: String
    public var names: [String: String]?

    public init(id: String, names: [String: String]? = nil) {
        self.id = id
        self.names = names
    }

    public func name(preferredLanguages: [String]) -> String {
        let names = self.names ?? [:]
        if let tag = LanguageTag.bestMatch(available: Array(names.keys),
                                           preferred: preferredLanguages),
           let value = names[tag] {
            return value
        }
        return names.sorted { $0.key < $1.key }.first?.value ?? id
    }
}

public struct TemplateLibraryLocalization: Codable, Equatable, Sendable {
    public var name: String?
    public var description: String?

    public init(name: String? = nil, description: String? = nil) {
        self.name = name
        self.description = description
    }
}

/// 模板作者。名称必填；主页链接可选，仅允许 HTTPS（本地开发允许 loopback HTTP）。
public struct TemplateLibraryAuthor: Codable, Equatable, Sendable {
    public var name: String
    public var url: String?

    public init(name: String, url: String? = nil) {
        self.name = name
        self.url = url
    }
}

public struct TemplateLibraryListing: Codable, Equatable, Sendable {
    public var tagline: String?
    public var highlights: [String]?

    public init(tagline: String? = nil, highlights: [String]? = nil) {
        self.tagline = tagline
        self.highlights = highlights
    }
}

public struct TemplateLibraryPreview: Codable, Equatable, Sendable {
    /// `live`（v1）或 `poster`（预留）。
    public var mode: String?
    public var url: String?
    public var width: Int?
    public var height: Int?

    public init(mode: String? = nil, url: String? = nil,
                width: Int? = nil, height: Int? = nil) {
        self.mode = mode
        self.url = url
        self.width = width
        self.height = height
    }
}

public struct TemplateLibraryPayload: Codable, Equatable, Sendable {
    public var url: String
    public var fileName: String
    public var bytes: Int
    public var sha256: String
    public var contentType: String?
    /// 官网手动下载用的 zip（HTML + sidecars）；App 安装只使用 `url`。
    public var bundleURL: String?

    public init(url: String, fileName: String, bytes: Int,
                sha256: String, contentType: String? = nil,
                bundleURL: String? = nil) {
        self.url = url
        self.fileName = fileName
        self.bytes = bytes
        self.sha256 = sha256
        self.contentType = contentType
        self.bundleURL = bundleURL
    }
}

/// 1.4 随 App 播种的模板哈希，用于 1.5 首次启动时认领未修改的旧副本。
public struct LegacyTemplateManifest: Codable, Equatable, Sendable {
    public var id: String
    public var file: String
    public var version: String
    public var sha256: String
    public var bytes: Int?

    public init(id: String, file: String, version: String,
                sha256: String, bytes: Int? = nil) {
        self.id = id
        self.file = file
        self.version = version
        self.sha256 = sha256
        self.bytes = bytes
    }
}

public struct LegacyTemplateIndex: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var sourceVersion: String?
    public var templates: [LegacyTemplateManifest]

    public init(schemaVersion: Int = 1, sourceVersion: String? = nil,
                templates: [LegacyTemplateManifest] = []) {
        self.schemaVersion = schemaVersion
        self.sourceVersion = sourceVersion
        self.templates = templates
    }
}

public struct TemplateLibraryChangelogEntry: Codable, Equatable, Sendable {
    public var date: String?
    public var notes: [String: String]?

    public init(date: String? = nil, notes: [String: String]? = nil) {
        self.date = date
        self.notes = notes
    }
}

public struct TemplateLibraryEntry: Codable, Equatable, Sendable {
    public var id: String
    public var version: String
    public var file: String
    public var order: Int?
    public var minAppVersion: String?
    public var category: String?
    public var tags: [String]?
    public var author: TemplateLibraryAuthor?
    public var defaultLanguage: String?
    public var fallbackLanguage: String?
    public var languages: [String: TemplateLibraryLocalization]?
    public var listing: [String: TemplateLibraryListing]?
    public var preview: TemplateLibraryPreview?
    public var payload: TemplateLibraryPayload
    public var pages: [String: String]?
    public var changelog: [String: TemplateLibraryChangelogEntry]?

    public init(id: String, version: String, file: String,
                order: Int? = nil, minAppVersion: String? = nil,
                category: String? = nil, tags: [String]? = nil,
                author: TemplateLibraryAuthor? = nil,
                defaultLanguage: String? = nil, fallbackLanguage: String? = nil,
                languages: [String: TemplateLibraryLocalization]? = nil,
                listing: [String: TemplateLibraryListing]? = nil,
                preview: TemplateLibraryPreview? = nil,
                payload: TemplateLibraryPayload,
                pages: [String: String]? = nil,
                changelog: [String: TemplateLibraryChangelogEntry]? = nil) {
        self.id = id
        self.version = version
        self.file = file
        self.order = order
        self.minAppVersion = minAppVersion
        self.category = category
        self.tags = tags
        self.author = author
        self.defaultLanguage = defaultLanguage
        self.fallbackLanguage = fallbackLanguage
        self.languages = languages
        self.listing = listing
        self.preview = preview
        self.payload = payload
        self.pages = pages
        self.changelog = changelog
    }

    // MARK: - 展示辅助

    public var minimumAppVersion: String { minAppVersion ?? "0.0.0" }

    public var sortOrder: Int { order ?? Int.max }

    /// 按偏好语言解析模板名称/简介；回落到 default、fallback、任意语言。
    public func localization(preferredLanguages: [String]) -> (language: String, value: TemplateLibraryLocalization)? {
        let values = languages ?? [:]
        guard !values.isEmpty else { return nil }
        let preferred = preferenceChain(preferredLanguages)
        if let tag = LanguageTag.bestMatch(available: Array(values.keys), preferred: preferred),
           let value = values[tag] {
            return (tag, value)
        }
        if let tag = values.keys.sorted().first, let value = values[tag] {
            return (tag, value)
        }
        return nil
    }

    public func localizedName(preferredLanguages: [String]) -> String {
        localization(preferredLanguages: preferredLanguages)?.value.name ?? file
    }

    public func localizedDescription(preferredLanguages: [String]) -> String {
        localization(preferredLanguages: preferredLanguages)?.value.description ?? ""
    }

    public func listing(preferredLanguages: [String]) -> TemplateLibraryListing? {
        let values = listing ?? [:]
        guard !values.isEmpty else { return nil }
        let preferred = preferenceChain(preferredLanguages)
        if let tag = LanguageTag.bestMatch(available: Array(values.keys), preferred: preferred) {
            return values[tag]
        }
        return values.keys.sorted().first.flatMap { values[$0] }
    }

    public func pageURLString(preferredLanguages: [String]) -> String? {
        let values = pages ?? [:]
        guard !values.isEmpty else { return nil }
        let preferred = preferenceChain(preferredLanguages)
        if let tag = LanguageTag.bestMatch(available: Array(values.keys), preferred: preferred) {
            return values[tag]
        }
        return values.keys.sorted().first.flatMap { values[$0] }
    }

    /// 当前版本是否在 changelog 中。
    public var hasCurrentChangelog: Bool {
        changelog?[version] != nil
    }

    /// 按版本号从新到旧。
    public var changelogEntries: [(version: String, entry: TemplateLibraryChangelogEntry)] {
        (changelog ?? [:])
            .map { (version: $0.key, entry: $0.value) }
            .sorted { VersionNumber.compare($0.version, $1.version) == .orderedDescending }
    }

    public func changelogNotes(version: String,
                               preferredLanguages: [String]) -> String? {
        let notes = changelog?[version]?.notes ?? [:]
        guard !notes.isEmpty else { return nil }
        let preferred = preferenceChain(preferredLanguages)
        if let tag = LanguageTag.bestMatch(available: Array(notes.keys), preferred: preferred) {
            return notes[tag]
        }
        return notes.keys.sorted().first.flatMap { notes[$0] }
    }

    private func preferenceChain(_ preferredLanguages: [String]) -> [String] {
        // 与 HTML 元数据解析一致：偏好语言 → fallback → default。
        var chain = preferredLanguages
        if let fallbackLanguage, !chain.contains(where: { LanguageTag.matches($0, fallbackLanguage) }) {
            chain.append(fallbackLanguage)
        }
        if let defaultLanguage, !chain.contains(where: { LanguageTag.matches($0, defaultLanguage) }) {
            chain.append(defaultLanguage)
        }
        return chain
    }
}

public extension Array where Element == TemplateLibraryEntry {
    /// 官方排序：`pinshell:order` 升序，其次 id。
    func sortedForLibrary() -> [Element] {
        sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
    }
}
