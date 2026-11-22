import XCTest
@testable import PinShellCore

final class HTMLTemplateEditorTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PinShellEditorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testCreatesMissingMetaAndUpdatesExistingOnes() throws {
        let url = temporaryDirectory.appendingPathComponent("panel.html")
        try """
        <!doctype html>
        <html><head>
        <title>Old</title>
        <meta name="description" content="Old desc">
        <meta content="240x80" name="pinshell:size">
        </head><body>hello</body></html>
        """.write(to: url, atomically: true, encoding: .utf8)

        try HTMLTemplateEditor.apply(HTMLTemplateEdit(
            title: "New & Better",
            subtitle: "New desc",
            size: WindowSize(width: 320, height: 120),
            position: .anchor(.bottomRight),
            passthrough: true,
            opacity: 0.85,
            radius: 18,
            order: 7
        ), to: url)

        let html = try String(contentsOf: url, encoding: .utf8)
        let metadata = HTMLTemplateMetadata.parse(html: html)

        XCTAssertEqual(metadata.title, "New & Better")
        XCTAssertEqual(metadata.subtitle, "New desc")
        XCTAssertEqual(metadata.size, WindowSize(width: 320, height: 120))
        XCTAssertEqual(metadata.position, .anchor(.bottomRight))
        XCTAssertEqual(metadata.passthrough, true)
        XCTAssertEqual(metadata.opacity, 0.85)
        XCTAssertEqual(metadata.radius, 18)
        XCTAssertEqual(metadata.order, 7)
        XCTAssertTrue(html.contains("<body>hello</body>"))
        XCTAssertEqual(html.components(separatedBy: "pinshell:size").count - 1, 1)
    }

    func testUpdatesPinshellTitleAndSubtitleOverrides() throws {
        let url = temporaryDirectory.appendingPathComponent("override.html")
        try """
        <html><head>
        <title>Base</title>
        <meta name="pinshell:title" content="Override">
        <meta name="pinshell:subtitle" content="Override sub">
        </head></html>
        """.write(to: url, atomically: true, encoding: .utf8)

        try HTMLTemplateEditor.apply(HTMLTemplateEdit(title: "Edited", subtitle: "Edited sub"), to: url)
        let metadata = HTMLTemplateMetadata.parse(html: try String(contentsOf: url, encoding: .utf8))

        XCTAssertEqual(metadata.title, "Edited")
        XCTAssertEqual(metadata.subtitle, "Edited sub")
    }

    func testWritesIntoI18nBlockForCurrentLanguage() throws {
        let url = temporaryDirectory.appendingPathComponent("block.html")
        try """
        <html lang="zh-Hans"><head>
        <script type="application/json" id="pinshell:i18n">
        {
          "default": "zh-Hans",
          "fallback": "en",
          "languages": {
            "zh-Hans": { "meta": { "name": "待办事项", "description": "中文简介" } },
            "en": { "meta": { "name": "Todo List", "description": "English summary" }, "ui": { "title": "Todo List" } }
          }
        }
        </script>
        <title>待办事项</title>
        <meta name="description" content="中文简介">
        </head><body></body></html>
        """.write(to: url, atomically: true, encoding: .utf8)

        try HTMLTemplateEditor.apply(HTMLTemplateEdit(
            title: "Renamed Todo",
            subtitle: "New summary",
            language: "en"
        ), to: url)

        let html = try String(contentsOf: url, encoding: .utf8)
        let en = HTMLTemplateMetadata.parse(html: html, preferredLanguages: ["en"])
        XCTAssertEqual(en.title, "Renamed Todo")
        XCTAssertEqual(en.subtitle, "New summary")
        let zh = HTMLTemplateMetadata.parse(html: html, preferredLanguages: ["zh-Hans"])
        XCTAssertEqual(zh.title, "待办事项")
        XCTAssertEqual(zh.subtitle, "中文简介")
        XCTAssertTrue(html.contains("\"title\" : \"Todo List\""))
    }

    func testEditingBlockDefaultLanguageUpdatesTitleFallback() throws {
        let url = temporaryDirectory.appendingPathComponent("block-default.html")
        try """
        <html lang="zh-Hans"><head>
        <script type="application/json" id="pinshell:i18n">
        {
          "default": "zh-Hans",
          "fallback": "en",
          "languages": {
            "zh-Hans": { "meta": { "name": "待办事项", "description": "中文简介" } },
            "en": { "meta": { "name": "Todo List", "description": "English summary" } }
          }
        }
        </script>
        <title>待办事项</title>
        <meta name="description" content="中文简介">
        </head><body></body></html>
        """.write(to: url, atomically: true, encoding: .utf8)

        try HTMLTemplateEditor.apply(HTMLTemplateEdit(
            title: "我的待办",
            subtitle: "新的简介",
            language: "zh-Hans"
        ), to: url)

        let html = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(html.contains("<title>我的待办</title>"))
        XCTAssertTrue(html.contains("content=\"新的简介\""))
        let metadata = HTMLTemplateMetadata.parse(html: html, preferredLanguages: ["zh-Hans"])
        XCTAssertEqual(metadata.title, "我的待办")
        XCTAssertEqual(metadata.subtitle, "新的简介")
    }

    func testWritesNonDefaultLanguageAsMetaVariant() throws {
        let url = temporaryDirectory.appendingPathComponent("i18n.html")
        try """
        <html lang="zh-Hans"><head>
        <title>待办事项</title>
        <meta name="description" content="中文简介">
        </head><body></body></html>
        """.write(to: url, atomically: true, encoding: .utf8)

        try HTMLTemplateEditor.apply(HTMLTemplateEdit(
            title: "Todo List",
            subtitle: "English summary",
            language: "en"
        ), to: url)

        let html = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(html.contains("<title>待办事项</title>"))
        XCTAssertTrue(html.contains("<meta name=\"description\" content=\"中文简介\">"))
        XCTAssertTrue(html.contains("name=\"pinshell:title\" content=\"Todo List\" lang=\"en\"")
                      || html.contains("name=\"pinshell:title\" lang=\"en\" content=\"Todo List\""))

        let en = HTMLTemplateMetadata.parse(html: html, preferredLanguages: ["en"])
        XCTAssertEqual(en.title, "Todo List")
        XCTAssertEqual(en.subtitle, "English summary")

        let zh = HTMLTemplateMetadata.parse(html: html, preferredLanguages: ["zh-Hans"])
        XCTAssertEqual(zh.title, "待办事项")
        XCTAssertEqual(zh.subtitle, "中文简介")
    }

    func testEditingDefaultLanguageLeavesVariantsUntouched() throws {
        let url = temporaryDirectory.appendingPathComponent("i18n-default.html")
        try """
        <html lang="zh-Hans"><head>
        <title>待办事项</title>
        <meta name="description" content="中文简介">
        <meta name="pinshell:title" lang="en" content="Todo List">
        <meta name="pinshell:subtitle" lang="en" content="English summary">
        </head><body></body></html>
        """.write(to: url, atomically: true, encoding: .utf8)

        try HTMLTemplateEditor.apply(HTMLTemplateEdit(
            title: "我的待办",
            subtitle: "新的简介",
            language: "zh-Hans"
        ), to: url)

        let html = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(html.contains("<title>我的待办</title>"))
        XCTAssertTrue(html.contains("content=\"新的简介\""))
        XCTAssertTrue(html.contains("lang=\"en\" content=\"Todo List\"")
                      || html.contains("content=\"Todo List\" lang=\"en\""))

        let en = HTMLTemplateMetadata.parse(html: html, preferredLanguages: ["en"])
        XCTAssertEqual(en.title, "Todo List")
        XCTAssertEqual(en.subtitle, "English summary")
    }

    func testEditingAnExistingLanguageVariantUpdatesIt() throws {
        let url = temporaryDirectory.appendingPathComponent("i18n-update.html")
        try """
        <html lang="zh-Hans"><head>
        <title>待办事项</title>
        <meta name="pinshell:title" lang="en-US" content="Old English">
        </head></html>
        """.write(to: url, atomically: true, encoding: .utf8)

        try HTMLTemplateEditor.apply(HTMLTemplateEdit(
            title: "New English",
            language: "en"
        ), to: url)

        let en = HTMLTemplateMetadata.parse(
            html: try String(contentsOf: url, encoding: .utf8),
            preferredLanguages: ["en"]
        )
        XCTAssertEqual(en.title, "New English")
        let html = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(html.components(separatedBy: "pinshell:title").count - 1, 1)
    }

    func testInsertsHeadWhenMissingAndEscapesAttributes() throws {
        let url = temporaryDirectory.appendingPathComponent("nohead.html")
        try "<html><body>x</body></html>".write(to: url, atomically: true, encoding: .utf8)

        try HTMLTemplateEditor.apply(HTMLTemplateEdit(
            title: "A \"quoted\" <title>",
            size: WindowSize(width: 100, height: 50),
            position: .absolute(x: 12, y: 34)
        ), to: url)

        let html = try String(contentsOf: url, encoding: .utf8)
        let metadata = HTMLTemplateMetadata.parse(html: html)

        XCTAssertEqual(metadata.title, "A \"quoted\" <title>")
        XCTAssertEqual(metadata.size, WindowSize(width: 100, height: 50))
        XCTAssertEqual(metadata.position, .absolute(x: 12, y: 34))
    }

    func testPreservesFilePermissions() throws {
        let url = temporaryDirectory.appendingPathComponent("perm.html")
        try "<html><head></head></html>".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: url.path)

        try HTMLTemplateEditor.apply(HTMLTemplateEdit(radius: 12), to: url)

        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o640)
    }
}
