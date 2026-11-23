import XCTest
@testable import PinShellCore

final class TemplateSourceManifestTests: XCTestCase {
    private func manifest() -> TemplateSourceManifest {
        TemplateSourceManifest(
            id: "todo",
            version: "1.0.0",
            releaseDate: "2026-11-23",
            minAppVersion: "1.4.0",
            category: "productivity",
            tags: ["tasks", "eisenhower"],
            listing: [
                "zh-Hans": TemplateLibraryListing(
                    tagline: "把今天安放在屏幕一角。",
                    highlights: ["列表与四象限"]),
                "en": TemplateLibraryListing(
                    tagline: "Keep today in the corner of your screen.",
                    highlights: ["List and Eisenhower views"]),
            ],
            changelog: [
                "1.0.0": TemplateLibraryChangelogEntry(
                    date: "2026-11-23",
                    notes: ["zh-Hans": "首个在线版本。", "en": "First library release."])
            ])
    }

    func testValidManifestPasses() throws {
        XCTAssertNoThrow(try TemplateSourceManifestValidator.validate(
            manifest(), expectedID: "todo", categories: ["productivity"]))
    }

    func testRejectsIDMismatch() {
        XCTAssertThrowsError(try TemplateSourceManifestValidator.validate(
            manifest(), expectedID: "other", categories: ["productivity"])) {
            XCTAssertEqual($0 as? TemplateLibraryValidationError, .invalidID("todo"))
        }
    }

    func testRejectsUnknownCategory() {
        XCTAssertThrowsError(try TemplateSourceManifestValidator.validate(
            manifest(), expectedID: "todo", categories: ["monitoring"])) {
            XCTAssertEqual($0 as? TemplateLibraryValidationError,
                           .invalidCategory("productivity"))
        }
    }

    func testRejectsMissingCurrentChangelog() {
        var value = manifest()
        value.version = "1.1.0"
        XCTAssertThrowsError(try TemplateSourceManifestValidator.validate(
            value, expectedID: "todo", categories: ["productivity"])) {
            XCTAssertEqual($0 as? TemplateLibraryValidationError,
                           .missingChangelog("todo"))
        }
    }

    func testRejectsBadDatesAndVersions() {
        var value = manifest()
        value.version = "1.0"
        XCTAssertThrowsError(try TemplateSourceManifestValidator.validate(
            value, expectedID: "todo", categories: ["productivity"]))

        value = manifest()
        value.releaseDate = "2026/11/23"
        XCTAssertThrowsError(try TemplateSourceManifestValidator.validate(
            value, expectedID: "todo", categories: ["productivity"]))
    }

    func testDecodesSourceManifest() throws {
        let data = try JSONEncoder().encode(manifest())
        let decoded = try JSONDecoder().decode(TemplateSourceManifest.self, from: data)
        XCTAssertEqual(decoded.id, "todo")
        XCTAssertEqual(decoded.listing?["zh-Hans"]?.highlights, ["列表与四象限"])
        XCTAssertEqual(decoded.changelog?["1.0.0"]?.notes?["en"],
                       "First library release.")
    }
}

final class TemplateI18nCoverageUtilityTests: XCTestCase {
    private let validHTML = """
    <html lang="zh-Hans"><head>
    <script type="application/json" id="pinshell:i18n">
    {
      "default": "zh-Hans",
      "fallback": "en",
      "languages": {
        "zh-Hans": { "meta": { "name": "待办事项", "description": "中文简介" } },
        "en": {
          "meta": { "name": "Todo List", "description": "English summary" },
          "ui": { "title": "Todo List" }
        }
      }
    }
    </script>
    <title>待办事项</title>
    </head><body><span data-i18n="title">待办事项</span></body></html>
    """

    func testValidCoveragePasses() throws {
        XCTAssertNoThrow(try TemplateI18nCoverage.validate(html: validHTML))
        XCTAssertEqual(TemplateI18nCoverage.referencedKeys(in: validHTML), ["title"])
    }

    func testMissingKeyIsReported() {
        let html = validHTML.replacingOccurrences(
            of: #""ui": { "title": "Todo List" }"#,
            with: #""ui": {}"#)
        let problems = TemplateI18nCoverage.problems(in: html)
        XCTAssertTrue(problems.contains { $0.contains("missing keys") })
    }

    func testMissingBlockIsReported() {
        let problems = TemplateI18nCoverage.problems(in: "<html></html>")
        XCTAssertEqual(problems, ["missing pinshell:i18n block"])
    }

    func testEmptyDescriptionIsReported() {
        let html = validHTML.replacingOccurrences(of: "English summary", with: "")
        let problems = TemplateI18nCoverage.problems(in: html)
        XCTAssertTrue(problems.contains { $0.contains("en: empty description") })
    }
}
