import XCTest
@testable import PinShellCore

final class HTMLTemplateMetadataTests: XCTestCase {
    func testParsesHeadMetadataInAnyAttributeOrder() {
        let html = """
        <!doctype html>
        <html><head>
        <title> 订阅 &amp; 进度 </title>
        <meta content="280x64" name="pinshell:size">
        <meta content='bottom-right' name='pinshell:position'>
        <meta name="pinshell:passthrough" content="on">
        <meta name="pinshell:opacity" content="1.4">
        <meta name="pinshell:radius" content="18">
        <meta name="pinshell:order" content="3">
        <meta name="description" content="显示   目标">
        </head></html>
        """

        let metadata = HTMLTemplateMetadata.parse(html: html)

        XCTAssertEqual(metadata.title, "订阅 & 进度")
        XCTAssertEqual(metadata.subtitle, "显示 目标")
        XCTAssertEqual(metadata.size, WindowSize(width: 280, height: 64))
        XCTAssertEqual(metadata.position, .anchor(.bottomRight))
        XCTAssertEqual(metadata.passthrough, true)
        XCTAssertEqual(metadata.opacity, 1.0)
        XCTAssertEqual(metadata.radius, 18)
        XCTAssertEqual(metadata.order, 3)
    }

    func testIgnoresCommentedTagsAndSupportsOverrides() {
        let html = """
        <html><head>
        <title>Fallback</title>
        <!-- <meta name="pinshell:title" content="Commented"> -->
        <meta name="pinshell:title" content="Agent Panel">
        <meta name="pinshell:subtitle" content="Interactive">
        <meta name="description" content="Standard Description">
        </head></html>
        """

        let metadata = HTMLTemplateMetadata.parse(html: html)

        XCTAssertEqual(metadata.title, "Agent Panel")
        XCTAssertEqual(metadata.subtitle, "Interactive")
    }

    func testMissingMetadataIsEmpty() {
        let metadata = HTMLTemplateMetadata.parse(html: "<html><body>hello</body></html>")
        XCTAssertNil(metadata.title)
        XCTAssertNil(metadata.subtitle)
        XCTAssertNil(metadata.size)
        XCTAssertNil(metadata.position)
        XCTAssertNil(metadata.passthrough)
        XCTAssertNil(metadata.opacity)
        XCTAssertNil(metadata.radius)
        XCTAssertNil(metadata.order)
        XCTAssertTrue(metadata.windowSpec.isEmpty)
    }

    func testFillingMissingOnlyFillsGaps() {
        let primary = HTMLTemplateMetadata(title: "Mine",
                                           size: WindowSize(width: 100, height: 50))
        let fallback = HTMLTemplateMetadata(title: "Builtin",
                                            subtitle: "Desc",
                                            size: WindowSize(width: 240, height: 80),
                                            order: 3)

        let merged = primary.fillingMissing(from: fallback)

        XCTAssertEqual(merged.title, "Mine")
        XCTAssertEqual(merged.subtitle, "Desc")
        XCTAssertEqual(merged.size, WindowSize(width: 100, height: 50))
        XCTAssertEqual(merged.order, 3)
    }

    func testInvalidValuesAreIgnored() {
        let html = """
        <meta name="pinshell:size" content="wide">
        <meta name="pinshell:position" content="somewhere">
        <meta name="pinshell:opacity" content="loud">
        <meta name="pinshell:radius" content="-1">
        <meta name="pinshell:order" content="first">
        """
        let metadata = HTMLTemplateMetadata.parse(html: html)
        XCTAssertNil(metadata.size)
        XCTAssertNil(metadata.position)
        XCTAssertNil(metadata.opacity)
        XCTAssertNil(metadata.radius)
        XCTAssertNil(metadata.order)
    }
}
