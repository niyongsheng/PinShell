import Foundation
import PinShellCore

struct BuiltTemplate {
    let manifest: TemplateSourceManifest
    let metadata: HTMLTemplateMetadata
    let i18n: TemplateI18n
    let htmlData: Data
    let html: String
    let sha256: String
    let entry: TemplateLibraryEntry
}

struct BuiltCatalog {
    let index: TemplateLibraryIndex
    let templates: [BuiltTemplate]
}

enum CatalogBuilder {
    static func build(paths: RepoPaths,
                      site: SiteConfig,
                      appVersion: String,
                      output: URL) throws -> BuiltCatalog {
        let fm = FileManager.default
        let directoryEntries = try fm.contentsOfDirectory(
            at: paths.templates,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !directoryEntries.isEmpty else {
            throw BuilderError(message: "no templates found in \(paths.templates.path)")
        }

        let legacy = try paths.loadLegacy()
        let legacyByID = Dictionary(uniqueKeysWithValues:
            (legacy?.templates ?? []).map { ($0.id, $0) })
        let categoryIDs = Set(site.categories.map(\.id))

        var built: [BuiltTemplate] = []
        var seenIDs = Set<String>()
        var seenOrders = Set<Int>()

        for directory in directoryEntries {
            let id = directory.lastPathComponent
            guard seenIDs.insert(id).inserted else {
                throw BuilderError(message: "duplicate template directory \(id)")
            }
            let fileNames = try fm.contentsOfDirectory(atPath: directory.path)
                .filter { !$0.hasPrefix(".") }
                .sorted()
            let expected = ["template.json", "\(id).html"].sorted()
            guard fileNames == expected else {
                throw BuilderError(
                    message: "\(id): source directory must contain exactly \(expected), got \(fileNames)")
            }

            let manifestURL = directory.appendingPathComponent("template.json")
            let manifest: TemplateSourceManifest
            do {
                manifest = try JSONDecoder().decode(
                    TemplateSourceManifest.self,
                    from: Data(contentsOf: manifestURL))
            } catch {
                throw BuilderError(message: "\(id): invalid template.json: \(error)")
            }
            do {
                try TemplateSourceManifestValidator.validate(
                    manifest, expectedID: id, categories: categoryIDs)
            } catch {
                throw BuilderError(message: "\(id): \(error)")
            }
            guard let minAppVersion = manifest.minAppVersion else {
                throw BuilderError(message: "\(id): missing minAppVersion")
            }
            if VersionNumber.compare(minAppVersion, appVersion) == .orderedDescending {
                throw BuilderError(
                    message: "\(id): minAppVersion \(minAppVersion) is newer than app \(appVersion)")
            }

            let htmlURL = directory.appendingPathComponent("\(id).html")
            let data = try Data(contentsOf: htmlURL)
            guard data.count <= TemplateLibraryValidation.maxPayloadBytes else {
                throw BuilderError(
                    message: "\(id): HTML exceeds \(TemplateLibraryValidation.maxPayloadBytes) bytes")
            }
            guard let html = String(data: data, encoding: .utf8) else {
                throw BuilderError(message: "\(id): HTML is not UTF-8")
            }

            do {
                try TemplateI18nCoverage.validate(html: html)
            } catch {
                throw BuilderError(message: "\(id): \(error)")
            }
            guard let i18n = TemplateI18n.parse(html: html),
                  let defaultLanguage = i18n.defaultLanguage,
                  let fallbackLanguage = i18n.fallbackLanguage else {
                throw BuilderError(message: "\(id): i18n block missing default/fallback")
            }
            guard LanguageTag.matches(defaultLanguage, "zh-Hans") else {
                throw BuilderError(message: "\(id): default language must be zh-Hans")
            }
            guard LanguageTag.matches(fallbackLanguage, "en") else {
                throw BuilderError(message: "\(id): fallback language must be en")
            }

            let metadata = HTMLTemplateMetadata.parse(html: html)
            guard let documentLanguage = metadata.documentLanguage else {
                throw BuilderError(message: "\(id): missing <html lang>")
            }
            guard LanguageTag.matches(documentLanguage, defaultLanguage) else {
                throw BuilderError(
                    message: "\(id): <html lang> \(documentLanguage) does not match \(defaultLanguage)")
            }
            guard let title = metadata.title, !title.isEmpty else {
                throw BuilderError(message: "\(id): missing title")
            }
            guard let size = metadata.size,
                  size.width >= 80, size.height >= 40 else {
                throw BuilderError(message: "\(id): pinshell:size is missing or below 80x40")
            }
            if let order = metadata.order, !seenOrders.insert(order).inserted {
                throw BuilderError(message: "\(id): duplicate pinshell:order \(order)")
            }

            var languages: [String: TemplateLibraryLocalization] = [:]
            for (tag, value) in i18n.languages {
                guard let name = value.name, !name.isEmpty,
                      let description = value.description, !description.isEmpty else {
                    throw BuilderError(message: "\(id)/\(tag): empty meta name/description")
                }
                languages[tag] = TemplateLibraryLocalization(
                    name: name, description: description)
            }

            try validateAssetReferences(html, id: id)

            let sha256 = FileDigest.sha256(of: data)
            if manifest.version == "1.0.0", let legacy = legacyByID[id] {
                guard legacy.sha256 == sha256 else {
                    throw BuilderError(
                        message: "\(id): v1.0.0 hash \(sha256) does not match frozen legacy hash \(legacy.sha256)")
                }
            }

            let payloadPath = "templates/\(id)/\(manifest.version)/\(id).html"
            let bundlePath = "templates/\(id)/\(manifest.version)/\(id)-\(manifest.version).zip"
            var pages: [String: String] = [:]
            for language in site.languages {
                pages[language.id] = "\(language.pathPrefix)templates/\(id)/"
            }
            let width = Int(size.width.rounded())
            let height = Int(size.height.rounded())
            let entry = TemplateLibraryEntry(
                id: id,
                version: manifest.version,
                file: "\(id).html",
                order: metadata.order,
                minAppVersion: manifest.minAppVersion,
                category: manifest.category,
                tags: manifest.tags,
                author: manifest.author,
                defaultLanguage: defaultLanguage,
                fallbackLanguage: fallbackLanguage,
                languages: languages,
                listing: manifest.listing,
                preview: TemplateLibraryPreview(
                    mode: "live",
                    url: payloadPath,
                    width: width,
                    height: height),
                payload: TemplateLibraryPayload(
                    url: payloadPath,
                    fileName: "\(id).html",
                    bytes: data.count,
                    sha256: sha256,
                    contentType: "text/html; charset=utf-8",
                    bundleURL: bundlePath),
                pages: pages,
                changelog: manifest.changelog
            )
            do {
                try TemplateLibraryValidation.validate(entry, categories: categoryIDs)
            } catch {
                throw BuilderError(message: "\(id): \(error)")
            }

            built.append(BuiltTemplate(
                manifest: manifest,
                metadata: metadata,
                i18n: i18n,
                htmlData: data,
                html: html,
                sha256: sha256,
                entry: entry))
        }

        // 首页策展列表：未知 ID、重复项或超出 hero 槽位的配置会让窗口静默缺失，构建期直接失败。
        let builtIDs = Set(built.map(\.entry.id))
        let curatedLists = [
            ("featured", site.featured),
            ("hero", site.hero ?? Array(site.featured.prefix(3))),
        ]
        for (name, ids) in curatedLists {
            guard !ids.isEmpty else {
                throw BuilderError(message: "site.json \(name) must list at least one template")
            }
            guard Set(ids).count == ids.count else {
                throw BuilderError(message: "site.json \(name) contains duplicate template ids")
            }
            if let unknown = ids.first(where: { !builtIDs.contains($0) }) {
                throw BuilderError(message: "site.json \(name) references unknown template \(unknown)")
            }
        }
        if let hero = site.hero, hero.count > 3 {
            throw BuilderError(message: "site.json hero supports at most 3 templates")
        }

        let index = TemplateLibraryIndex(
            schemaVersion: TemplateLibraryValidation.supportedSchemaVersion,
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            categories: site.categories,
            templates: built.map(\.entry).sortedForLibrary()
        )
        do {
            try TemplateLibraryValidation.validate(index)
        } catch {
            throw BuilderError(message: "generated catalog is invalid: \(error)")
        }

        try write(built: built, index: index, paths: paths, output: output)
        return BuiltCatalog(index: index, templates: built)
    }

    private static func validateAssetReferences(_ html: String, id: String) throws {
        let patterns = [
            #"<link\b[^>]*\bhref\s*=\s*["']([^"']+)["']"#,
            #"<script\b[^>]*\bsrc\s*=\s*["']([^"']+)["']"#,
        ]
        let allowedLocal = Set(["design-tokens.css", "pinshell-i18n.js"])
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(
                pattern: pattern, options: [.caseInsensitive]) else { continue }
            let ns = html as NSString
            for match in regex.matches(in: html,
                                       range: NSRange(location: 0, length: ns.length)) {
                guard match.numberOfRanges > 1 else { continue }
                let ref = ns.substring(with: match.range(at: 1))
                if ref.hasPrefix("https://") || ref.hasPrefix("data:") || ref.hasPrefix("#") {
                    continue
                }
                if allowedLocal.contains(ref) { continue }
                throw BuilderError(
                    message: "\(id): unsupported local asset reference \(ref)")
            }
        }
    }

    private static func write(built: [BuiltTemplate],
                              index: TemplateLibraryIndex,
                              paths: RepoPaths,
                              output: URL) throws {
        let fm = FileManager.default
        try? fm.removeItem(at: output)
        try fm.createDirectory(at: output, withIntermediateDirectories: true)

        let sidecars = ["design-tokens.css", "pinshell-i18n.js"]
        let sidecarURLs = try sidecars.map { ($0, try paths.sidecarURL(named: $0)) }
        for template in built {
            let directory = output
                .appendingPathComponent("templates/\(template.entry.id)/\(template.entry.version)",
                                        isDirectory: true)
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            try template.htmlData.write(
                to: directory.appendingPathComponent(template.entry.file),
                options: .atomic)
            for (name, source) in sidecarURLs {
                try? fm.removeItem(at: directory.appendingPathComponent(name))
                try fm.copyItem(at: source,
                                to: directory.appendingPathComponent(name))
            }
            try createBundle(directory: directory,
                             id: template.entry.id,
                             version: template.entry.version,
                             sidecars: sidecars)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(index)
        guard data.count <= TemplateLibraryValidation.maxCatalogBytes else {
            throw BuilderError(message: "library.json exceeds 2MB")
        }
        try data.write(to: output.appendingPathComponent("library.json"), options: .atomic)
    }

    /// 官网手动下载包：HTML + sidecars，平铺 zip。
    private static func createBundle(directory: URL,
                                     id: String,
                                     version: String,
                                     sidecars: [String]) throws {
        let zipName = "\(id)-\(version).zip"
        let zipURL = directory.appendingPathComponent(zipName)
        try? FileManager.default.removeItem(at: zipURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = directory
        process.arguments = ["-q", "-j", zipName, "\(id).html"] + sidecars
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(),
                                 encoding: .utf8) ?? ""
            throw BuilderError(message: "\(id): zip failed: \(message)")
        }
    }
}
