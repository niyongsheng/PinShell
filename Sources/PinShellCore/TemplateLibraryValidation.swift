import Foundation

public enum TemplateLibraryValidationError: Error, Equatable, CustomStringConvertible {
    case unsupportedSchema(Int)
    case duplicateID(String)
    case invalidID(String)
    case fileMismatch(id: String, file: String)
    case invalidVersion(String)
    case invalidDate(String)
    case missingChangelog(String)
    case invalidSHA256(String)
    case invalidPayloadSize(Int)
    case invalidPayloadURL(String)
    case invalidPageURL(String)
    case invalidCategory(String)
    case invalidTags(String)
    case invalidAuthor(String)
    case invalidPreview(String)
    case missingLocalization(String)
    case emptyLocalization(language: String, field: String)
    case invalidManifest(String)

    public var description: String {
        switch self {
        case .unsupportedSchema(let version):
            return "unsupported catalog schemaVersion \(version)"
        case .duplicateID(let id):
            return "duplicate template id \(id)"
        case .invalidID(let id):
            return "invalid template id \(id)"
        case .fileMismatch(let id, let file):
            return "template \(id) must use file \(id).html, got \(file)"
        case .invalidVersion(let version):
            return "invalid version \(version) (expected X.Y.Z)"
        case .invalidDate(let date):
            return "invalid date \(date) (expected YYYY-MM-DD)"
        case .missingChangelog(let id):
            return "template \(id) is missing a changelog entry for its current version"
        case .invalidSHA256(let hash):
            return "invalid sha256 \(hash)"
        case .invalidPayloadSize(let bytes):
            return "invalid payload size \(bytes)"
        case .invalidPayloadURL(let url):
            return "invalid payload URL \(url)"
        case .invalidPageURL(let url):
            return "invalid page URL \(url)"
        case .invalidCategory(let category):
            return "invalid category \(category)"
        case .invalidTags(let id):
            return "invalid tags for template \(id)"
        case .invalidAuthor(let id):
            return "invalid author for template \(id)"
        case .invalidPreview(let id):
            return "invalid preview for template \(id)"
        case .missingLocalization(let id):
            return "template \(id) is missing localized name/description"
        case .emptyLocalization(let language, let field):
            return "empty \(field) for language \(language)"
        case .invalidManifest(let message):
            return "invalid template manifest: \(message)"
        }
    }
}

public enum TemplateLibraryValidation {
    public static let supportedSchemaVersion = 1
    public static let maxPayloadBytes = 512 * 1024
    public static let maxCatalogBytes = 2 * 1024 * 1024
    public static let defaultLanguages = ["zh-Hans", "en"]

    private static let idRegex = try? NSRegularExpression(
        pattern: "^[a-z0-9]+(?:-[a-z0-9]+)*$"
    )
    private static let semverRegex = try? NSRegularExpression(
        pattern: "^[0-9]+\\.[0-9]+\\.[0-9]+$"
    )
    private static let dateRegex = try? NSRegularExpression(
        pattern: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$"
    )
    private static let tagRegex = try? NSRegularExpression(
        pattern: "^[a-z0-9-]{1,24}$"
    )
    private static let shaRegex = try? NSRegularExpression(
        pattern: "^[0-9a-f]{64}$"
    )

    public static func validate(_ index: TemplateLibraryIndex,
                                allowAbsolutePayloadURL: Bool = false) throws {
        guard index.schemaVersion == supportedSchemaVersion else {
            throw TemplateLibraryValidationError.unsupportedSchema(index.schemaVersion)
        }

        var categoryIDs = Set<String>()
        for category in index.categoryList {
            guard isValidID(category.id) else {
                throw TemplateLibraryValidationError.invalidCategory(category.id)
            }
            categoryIDs.insert(category.id)
            for (language, name) in category.names ?? [:] {
                guard !language.isEmpty, !name.isEmpty else {
                    throw TemplateLibraryValidationError.invalidCategory(category.id)
                }
            }
        }

        var seen = Set<String>()
        for entry in index.templates {
            guard seen.insert(entry.id).inserted else {
                throw TemplateLibraryValidationError.duplicateID(entry.id)
            }
            try validate(entry,
                         categories: categoryIDs.isEmpty ? nil : categoryIDs,
                         allowAbsolutePayloadURL: allowAbsolutePayloadURL)
        }
    }

    public static func validate(_ entry: TemplateLibraryEntry,
                                categories: Set<String>? = nil,
                                allowAbsolutePayloadURL: Bool = false) throws {
        guard isValidID(entry.id), entry.id.count <= 64 else {
            throw TemplateLibraryValidationError.invalidID(entry.id)
        }
        guard entry.file == "\(entry.id).html" else {
            throw TemplateLibraryValidationError.fileMismatch(id: entry.id, file: entry.file)
        }
        guard isSemver(entry.version) else {
            throw TemplateLibraryValidationError.invalidVersion(entry.version)
        }
        guard let minAppVersion = entry.minAppVersion, isSemver(minAppVersion) else {
            throw TemplateLibraryValidationError.invalidVersion(entry.minAppVersion ?? "")
        }
        if let order = entry.order, order < 0 {
            throw TemplateLibraryValidationError.invalidVersion("order \(order)")
        }

        if let category = entry.category {
            guard isValidID(category) else {
                throw TemplateLibraryValidationError.invalidCategory(category)
            }
            if let categories, !categories.contains(category) {
                throw TemplateLibraryValidationError.invalidCategory(category)
            }
        }

        if let tags = entry.tags {
            let unique = Set(tags)
            guard !tags.isEmpty, tags.count <= 8, unique.count == tags.count,
                  tags.allSatisfy({ isValidTag($0) }) else {
                throw TemplateLibraryValidationError.invalidTags(entry.id)
            }
        }

        if let author = entry.author {
            try validateAuthor(author, templateID: entry.id)
        }

        try validateLanguages(entry)
        try validateChangelog(entry)
        try validatePreview(entry)
        try validatePayload(entry, allowAbsolutePayloadURL: allowAbsolutePayloadURL)

        for (_, page) in entry.pages ?? [:] {
            guard isAllowedPageURL(page) else {
                throw TemplateLibraryValidationError.invalidPageURL(page)
            }
        }
    }

    // MARK: - 字段校验

    public static func isValidID(_ value: String) -> Bool {
        matches(idRegex, value)
    }

    public static func isSemver(_ value: String) -> Bool {
        matches(semverRegex, value)
    }

    public static func isISODate(_ value: String) -> Bool {
        matches(dateRegex, value)
    }

    public static func isSHA256(_ value: String) -> Bool {
        matches(shaRegex, value)
    }

    /// 仓库内相对路径：不允许根路径、反斜杠、`.`/`..` 段。
    public static func isSafeRelativePath(_ value: String) -> Bool {
        guard !value.isEmpty,
              !value.hasPrefix("/"),
              !value.hasPrefix("//"),
              !value.contains("\\"),
              !value.contains(":") else { return false }
        let parts = value.split(separator: "/", omittingEmptySubsequences: true)
        guard !parts.isEmpty else { return false }
        return parts.allSatisfy { $0 != "." && $0 != ".." }
    }

    public static func isAllowedPayloadURL(_ value: String,
                                           allowAbsoluteHTTPS: Bool) -> Bool {
        if isSafeRelativePath(value) { return true }
        return allowAbsoluteHTTPS && isAllowedRemoteURL(value)
    }

    public static func isAllowedPageURL(_ value: String) -> Bool {
        isSafeRelativePath(value) || isAllowedRemoteURL(value)
    }

    /// 作者名称必填且为单行；主页链接可选，仅允许 HTTPS（本地开发允许 loopback HTTP）。
    public static func validateAuthor(_ author: TemplateLibraryAuthor,
                                      templateID: String) throws {
        let name = author.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 64,
              name == author.name,
              !name.contains(where: { $0.isNewline }) else {
            throw TemplateLibraryValidationError.invalidAuthor(templateID)
        }
        if let url = author.url, !isAllowedRemoteURL(url) {
            throw TemplateLibraryValidationError.invalidAuthor(templateID)
        }
    }

    public static func isAllowedCatalogURL(_ url: URL) -> Bool {
        isAllowedRemoteURL(url)
    }

    public static func isAllowedRemoteURL(_ value: String) -> Bool {
        guard let url = URL(string: value) else { return false }
        return isAllowedRemoteURL(url)
    }

    /// HTTPS 任意主机；HTTP 仅 loopback（本地开发）。
    public static func isAllowedRemoteURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              let host = url.host, !host.isEmpty else { return false }
        if scheme == "https" { return true }
        guard scheme == "http" else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    // MARK: - 复合字段

    private static func validateLanguages(_ entry: TemplateLibraryEntry) throws {
        let languages = entry.languages ?? [:]
        guard !languages.isEmpty else {
            throw TemplateLibraryValidationError.missingLocalization(entry.id)
        }
        guard let defaultLanguage = entry.defaultLanguage,
              languages.keys.contains(where: { LanguageTag.matches($0, defaultLanguage) }) else {
            throw TemplateLibraryValidationError.missingLocalization(entry.id)
        }
        if let fallback = entry.fallbackLanguage,
           !languages.keys.contains(where: { LanguageTag.matches($0, fallback) }) {
            throw TemplateLibraryValidationError.missingLocalization(entry.id)
        }

        for (language, value) in languages {
            guard let name = value.name, !name.isEmpty else {
                throw TemplateLibraryValidationError.emptyLocalization(
                    language: language, field: "name")
            }
            guard let description = value.description, !description.isEmpty else {
                throw TemplateLibraryValidationError.emptyLocalization(
                    language: language, field: "description")
            }
        }

        for required in defaultLanguages {
            guard languages.keys.contains(where: { LanguageTag.matches($0, required) }) else {
                throw TemplateLibraryValidationError.missingLocalization(entry.id)
            }
        }
    }

    private static func validateChangelog(_ entry: TemplateLibraryEntry) throws {
        guard let changelog = entry.changelog, !changelog.isEmpty else {
            throw TemplateLibraryValidationError.missingChangelog(entry.id)
        }
        guard let current = changelog[entry.version] else {
            throw TemplateLibraryValidationError.missingChangelog(entry.id)
        }
        if let date = current.date, !isISODate(date) {
            throw TemplateLibraryValidationError.invalidDate(date)
        }
        for (version, value) in changelog {
            guard isSemver(version) else {
                throw TemplateLibraryValidationError.invalidVersion(version)
            }
            if let date = value.date, !isISODate(date) {
                throw TemplateLibraryValidationError.invalidDate(date)
            }
        }
        let notes = current.notes ?? [:]
        for required in defaultLanguages {
            guard let tag = notes.keys.first(where: { LanguageTag.matches($0, required) }),
                  let text = notes[tag], !text.isEmpty else {
                throw TemplateLibraryValidationError.emptyLocalization(
                    language: required, field: "changelog")
            }
        }
    }

    private static func validatePreview(_ entry: TemplateLibraryEntry) throws {
        guard let preview = entry.preview else { return }
        let mode = preview.mode ?? "live"
        guard mode == "live" || mode == "poster" else {
            throw TemplateLibraryValidationError.invalidPreview(entry.id)
        }
        if mode == "live" {
            guard let url = preview.url, isAllowedPageURL(url) else {
                throw TemplateLibraryValidationError.invalidPreview(entry.id)
            }
            guard let width = preview.width, let height = preview.height,
                  width >= 80, height >= 40 else {
                throw TemplateLibraryValidationError.invalidPreview(entry.id)
            }
        } else if let url = preview.url, !isAllowedPageURL(url) {
            throw TemplateLibraryValidationError.invalidPreview(entry.id)
        }
    }

    private static func validatePayload(_ entry: TemplateLibraryEntry,
                                        allowAbsolutePayloadURL: Bool) throws {
        let payload = entry.payload
        guard payload.fileName == entry.file else {
            throw TemplateLibraryValidationError.fileMismatch(id: entry.id,
                                                              file: payload.fileName)
        }
        guard payload.bytes > 0, payload.bytes <= maxPayloadBytes else {
            throw TemplateLibraryValidationError.invalidPayloadSize(payload.bytes)
        }
        guard isSHA256(payload.sha256) else {
            throw TemplateLibraryValidationError.invalidSHA256(payload.sha256)
        }
        guard isAllowedPayloadURL(payload.url,
                                  allowAbsoluteHTTPS: allowAbsolutePayloadURL) else {
            throw TemplateLibraryValidationError.invalidPayloadURL(payload.url)
        }
        if let bundleURL = payload.bundleURL,
           !isAllowedPayloadURL(bundleURL, allowAbsoluteHTTPS: allowAbsolutePayloadURL) {
            throw TemplateLibraryValidationError.invalidPayloadURL(bundleURL)
        }
    }

    // MARK: - Helpers

    private static func matches(_ regex: NSRegularExpression?, _ value: String) -> Bool {
        guard let regex else { return false }
        let range = NSRange(location: 0, length: (value as NSString).length)
        return regex.firstMatch(in: value, range: range) != nil
    }

    private static func isValidTag(_ value: String) -> Bool {
        matches(tagRegex, value)
    }
}
