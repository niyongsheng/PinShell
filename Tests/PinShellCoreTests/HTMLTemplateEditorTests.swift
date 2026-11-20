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
