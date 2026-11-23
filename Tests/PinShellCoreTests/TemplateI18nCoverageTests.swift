import XCTest
@testable import PinShellCore

/// 校验在线模板库的源模板：i18n 完整、manifest 合法、v1.0.0 与冻结哈希一致。
final class TemplateI18nCoverageTests: XCTestCase {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // PinShellCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
    }

    private var templatesDirectory: URL {
        repoRoot.appendingPathComponent("website/templates")
    }

    private var legacyURL: URL {
        repoRoot.appendingPathComponent("Resources/legacy-templates.json")
    }

    private struct SiteSummary: Decodable {
        var categories: [TemplateLibraryCategory]
    }

    func testLibraryTemplatesDeclareCompleteI18nBlocks() throws {
        let site = try JSONDecoder().decode(
            SiteSummary.self,
            from: Data(contentsOf: repoRoot.appendingPathComponent("website/site.json")))
        let categories = Set(site.categories.map(\.id))
        let directories = try FileManager.default.contentsOfDirectory(
            at: templatesDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ).filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertFalse(directories.isEmpty)

        for directory in directories {
            let id = directory.lastPathComponent
            let htmlURL = directory.appendingPathComponent("\(id).html")
            let manifestURL = directory.appendingPathComponent("template.json")
            XCTAssertTrue(FileManager.default.fileExists(atPath: htmlURL.path), id)
            XCTAssertTrue(FileManager.default.fileExists(atPath: manifestURL.path), id)

            let html = try String(contentsOf: htmlURL, encoding: .utf8)
            XCTAssertNoThrow(try TemplateI18nCoverage.validate(html: html), id)

            let manifest = try JSONDecoder().decode(
                TemplateSourceManifest.self, from: Data(contentsOf: manifestURL))
            XCTAssertNoThrow(try TemplateSourceManifestValidator.validate(
                manifest, expectedID: id, categories: categories), id)

            let en = HTMLTemplateMetadata.parse(html: html, preferredLanguages: ["en-US"])
            XCTAssertEqual(en.resolvedLanguage, "en", id)
            XCTAssertFalse((en.title ?? "").isEmpty, id)

            let zh = HTMLTemplateMetadata.parse(html: html, preferredLanguages: ["zh-Hans-CN"])
            XCTAssertEqual(zh.resolvedLanguage, "zh-Hans", id)
            XCTAssertFalse((zh.title ?? "").isEmpty, id)
        }
    }

    func testLibraryTemplatesMatchFrozenLegacyHashes() throws {
        let legacy = try JSONDecoder().decode(
            LegacyTemplateIndex.self, from: Data(contentsOf: legacyURL))
        for template in legacy.templates {
            let htmlURL = templatesDirectory
                .appendingPathComponent(template.id)
                .appendingPathComponent(template.file)
            let manifestURL = templatesDirectory
                .appendingPathComponent(template.id)
                .appendingPathComponent("template.json")
            let manifest = try JSONDecoder().decode(
                TemplateSourceManifest.self, from: Data(contentsOf: manifestURL))
            guard manifest.version == template.version else { continue }
            XCTAssertEqual(try FileDigest.sha256(of: htmlURL), template.sha256, template.id)
        }
    }
}
