import Foundation

/// `website/templates/<id>/template.json` 的源 manifest。
/// 名称/简介/尺寸/order 不在这里重复维护，由 builder 从 HTML 提取。
public struct TemplateSourceManifest: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var id: String
    public var version: String
    public var releaseDate: String?
    public var minAppVersion: String?
    public var category: String
    public var tags: [String]?
    public var listing: [String: TemplateLibraryListing]?
    public var changelog: [String: TemplateLibraryChangelogEntry]?

    public init(schemaVersion: Int = 1,
                id: String,
                version: String,
                releaseDate: String? = nil,
                minAppVersion: String? = nil,
                category: String,
                tags: [String]? = nil,
                listing: [String: TemplateLibraryListing]? = nil,
                changelog: [String: TemplateLibraryChangelogEntry]? = nil) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.version = version
        self.releaseDate = releaseDate
        self.minAppVersion = minAppVersion
        self.category = category
        self.tags = tags
        self.listing = listing
        self.changelog = changelog
    }
}

public enum TemplateSourceManifestValidator {
    public static func validate(_ manifest: TemplateSourceManifest,
                                expectedID: String,
                                categories: Set<String>) throws {
        guard manifest.schemaVersion == TemplateLibraryValidation.supportedSchemaVersion else {
            throw TemplateLibraryValidationError.unsupportedSchema(manifest.schemaVersion)
        }
        guard TemplateLibraryValidation.isValidID(manifest.id),
              manifest.id == expectedID else {
            throw TemplateLibraryValidationError.invalidID(manifest.id)
        }
        guard TemplateLibraryValidation.isSemver(manifest.version) else {
            throw TemplateLibraryValidationError.invalidVersion(manifest.version)
        }
        guard let minAppVersion = manifest.minAppVersion,
              TemplateLibraryValidation.isSemver(minAppVersion) else {
            throw TemplateLibraryValidationError.invalidVersion(manifest.minAppVersion ?? "")
        }
        if let releaseDate = manifest.releaseDate,
           !TemplateLibraryValidation.isISODate(releaseDate) {
            throw TemplateLibraryValidationError.invalidDate(releaseDate)
        }
        guard TemplateLibraryValidation.isValidID(manifest.category) else {
            throw TemplateLibraryValidationError.invalidCategory(manifest.category)
        }
        if !categories.isEmpty, !categories.contains(manifest.category) {
            throw TemplateLibraryValidationError.invalidCategory(manifest.category)
        }

        if let tags = manifest.tags {
            let unique = Set(tags)
            guard !tags.isEmpty, tags.count <= 8, unique.count == tags.count,
                  tags.allSatisfy({ tag in
                      tag.range(of: "^[a-z0-9-]{1,24}$", options: .regularExpression) != nil
                  }) else {
                throw TemplateLibraryValidationError.invalidTags(manifest.id)
            }
        }

        for (language, listing) in manifest.listing ?? [:] {
            guard !language.isEmpty,
                  (listing.tagline?.isEmpty == false)
                    || (listing.highlights?.isEmpty == false) else {
                throw TemplateLibraryValidationError.invalidManifest(
                    "\(manifest.id): empty listing for \(language)")
            }
        }

        guard let changelog = manifest.changelog, !changelog.isEmpty else {
            throw TemplateLibraryValidationError.missingChangelog(manifest.id)
        }
        for (version, entry) in changelog {
            guard TemplateLibraryValidation.isSemver(version) else {
                throw TemplateLibraryValidationError.invalidVersion(version)
            }
            if let date = entry.date, !TemplateLibraryValidation.isISODate(date) {
                throw TemplateLibraryValidationError.invalidDate(date)
            }
        }
        guard let current = changelog[manifest.version] else {
            throw TemplateLibraryValidationError.missingChangelog(manifest.id)
        }
        for required in TemplateLibraryValidation.defaultLanguages {
            let notes = current.notes ?? [:]
            guard let tag = notes.keys.first(where: { LanguageTag.matches($0, required) }),
                  let text = notes[tag], !text.isEmpty else {
                throw TemplateLibraryValidationError.emptyLocalization(
                    language: required, field: "changelog")
            }
        }
    }
}
