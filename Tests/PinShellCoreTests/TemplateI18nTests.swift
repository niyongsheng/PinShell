import XCTest
@testable import PinShellCore

final class TemplateI18nTests: XCTestCase {
    private let html = """
    <html lang="zh-Hans"><head>
    <script type="application/json" id="pinshell:i18n">
    {
      "default": "zh-Hans",
      "fallback": "en",
      "languages": {
        "zh-Hans": { "meta": { "name": "待办事项", "description": "中文简介" } },
        "en": {
          "meta": { "name": "Todo List", "description": "English summary" },
          "ui": { "title": "Todo List", "lines": ["one", "two"] }
        }
      }
    }
    </script>
    <title>待办事项</title>
    </head></html>
    """

    func testParsesBlockMetadata() throws {
        let i18n = try XCTUnwrap(TemplateI18n.parse(html: html))
        XCTAssertEqual(i18n.defaultLanguage, "zh-Hans")
        XCTAssertEqual(i18n.fallbackLanguage, "en")
        XCTAssertEqual(i18n.languages["en"]?.name, "Todo List")
        XCTAssertEqual(i18n.languages["zh-Hans"]?.description, "中文简介")
    }

    func testMetadataResolvesBlockByPreferredLanguage() {
        let en = HTMLTemplateMetadata.parse(html: html, preferredLanguages: ["en-US"])
        XCTAssertEqual(en.title, "Todo List")
        XCTAssertEqual(en.subtitle, "English summary")
        XCTAssertEqual(en.resolvedLanguage, "en")
        XCTAssertEqual(en.documentLanguage, "zh-Hans")
        XCTAssertEqual(en.availableLanguages, ["en", "zh-Hans"])

        let zh = HTMLTemplateMetadata.parse(html: html, preferredLanguages: ["zh-CN"])
        XCTAssertEqual(zh.title, "待办事项")
        XCTAssertEqual(zh.subtitle, "中文简介")
        XCTAssertEqual(zh.resolvedLanguage, "zh-Hans")

        let fr = HTMLTemplateMetadata.parse(html: html, preferredLanguages: ["fr"])
        XCTAssertEqual(fr.title, "Todo List")   // fallback en
        XCTAssertEqual(fr.resolvedLanguage, "en")
    }

    func testBlockWinsOverLegacyMeta() {
        let withLegacy = html.replacingOccurrences(
            of: "</head>",
            with: #"<meta name="pinshell:title" lang="en" content="Legacy"></head>"#
        )
        let metadata = HTMLTemplateMetadata.parse(html: withLegacy, preferredLanguages: ["en"])
        XCTAssertEqual(metadata.title, "Todo List")
    }

    func testReplacingBlockPreservesUIAndUpdatesMeta() throws {
        let block = try XCTUnwrap(TemplateI18n.extractBlock(from: html))
        var json = try XCTUnwrap(block.json)
        var languages = json["languages"] as? [String: Any] ?? [:]
        var en = languages["en"] as? [String: Any] ?? [:]
        var meta = en["meta"] as? [String: Any] ?? [:]
        meta["name"] = "Renamed"
        en["meta"] = meta
        languages["en"] = en
        json["languages"] = languages

        let updated = TemplateI18n.replacingBlock(in: html, with: json)
        XCTAssertTrue(updated.contains(#""name" : "Renamed""#))
        XCTAssertTrue(updated.contains("\"lines\""))
        XCTAssertTrue(updated.contains("one"))
        XCTAssertTrue(updated.contains("待办事项"))
        let parsed = try XCTUnwrap(TemplateI18n.parse(html: updated))
        XCTAssertEqual(parsed.languages["en"]?.name, "Renamed")
    }

    func testScriptTerminatorIsEscaped() {
        let json: [String: Any] = ["value": "</script>"]
        let encoded = TemplateI18n.encode(json)
        XCTAssertTrue(encoded?.contains("<\\/script>") == true)
    }
}
