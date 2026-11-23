import Foundation
import PinShellCore

struct BuilderError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

struct SiteLanguage: Codable, Equatable {
    var id: String
    var htmlLang: String
    var label: String
    var shortLabel: String
    var pathPrefix: String
}

struct SiteConfig: Codable, Equatable {
    var name: String
    var tagline: [String: String]
    var downloadURL: String
    var githubURL: String
    var issuesURL: String
    var releasesURL: String
    var featured: [String]
    var languages: [SiteLanguage]
    var categories: [TemplateLibraryCategory]

    func language(id: String) -> SiteLanguage? {
        languages.first { $0.id == id }
    }

    var defaultLanguage: SiteLanguage {
        languages.first ?? SiteLanguage(id: "zh-Hans", htmlLang: "zh-Hans",
                                         label: "中文", shortLabel: "中",
                                         pathPrefix: "")
    }
}

struct RepoPaths {
    let root: URL

    var website: URL { root.appendingPathComponent("website", isDirectory: true) }
    var templates: URL { website.appendingPathComponent("templates", isDirectory: true) }
    var source: URL { website.appendingPathComponent("src", isDirectory: true) }
    var publicDir: URL { website.appendingPathComponent("public", isDirectory: true) }
    var resources: URL { root.appendingPathComponent("Resources", isDirectory: true) }
    var sidecars: URL { resources.appendingPathComponent("templates", isDirectory: true) }
    var logo: URL { resources.appendingPathComponent("logo.svg") }
    var legacyFile: URL { resources.appendingPathComponent("legacy-templates.json") }

    static func discover(explicitRoot: String? = nil) throws -> RepoPaths {
        if let explicitRoot {
            return RepoPaths(root: URL(fileURLWithPath: explicitRoot))
        }

        // 编译期路径：.../website/Sources/TemplateCatalogBuilder/RepoPaths.swift
        var candidate = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { candidate.deleteLastPathComponent() }
        if isRepoRoot(candidate) {
            return RepoPaths(root: candidate)
        }

        candidate = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<8 {
            if isRepoRoot(candidate) {
                return RepoPaths(root: candidate)
            }
            candidate.deleteLastPathComponent()
        }
        throw BuilderError(message: "could not locate PinShell repo root")
    }

    private static func isRepoRoot(_ url: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: url.appendingPathComponent("Package.swift").path)
            && fm.fileExists(atPath: url.appendingPathComponent("Sources/PinShellCore").path)
            && fm.fileExists(atPath: url.appendingPathComponent("website").path)
    }

    func loadSiteConfig() throws -> SiteConfig {
        let url = website.appendingPathComponent("site.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(SiteConfig.self, from: data)
    }

    func appVersion() throws -> String {
        let url = resources.appendingPathComponent("Info.plist")
        let data = try Data(contentsOf: url)
        guard let plist = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        ) as? [String: Any],
              let version = plist["CFBundleShortVersionString"] as? String,
              !version.isEmpty else {
            throw BuilderError(message: "CFBundleShortVersionString missing in Resources/Info.plist")
        }
        return version
    }

    func loadLegacy() throws -> LegacyTemplateIndex? {
        guard FileManager.default.fileExists(atPath: legacyFile.path) else { return nil }
        let data = try Data(contentsOf: legacyFile)
        return try JSONDecoder().decode(LegacyTemplateIndex.self, from: data)
    }

    func sidecarURL(named name: String) throws -> URL {
        let url = sidecars.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw BuilderError(message: "missing runtime sidecar \(name) in Resources/templates")
        }
        return url
    }
}
