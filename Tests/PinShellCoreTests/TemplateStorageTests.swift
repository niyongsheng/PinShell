import XCTest
@testable import PinShellCore

final class TemplateStorageTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PinShellStorageTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testWriteReadDeleteRoundTrip() throws {
        let html = "<html><body>hello</body></html>"
        let url = try TemplateStorage.write(name: "panel.html", html: html, in: directory)
        XCTAssertEqual(url.lastPathComponent, "panel.html")
        XCTAssertEqual(try TemplateStorage.read(name: "panel.html", in: directory).content, html)

        try TemplateStorage.delete(name: "panel.html", in: directory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testWriteDataPreservesExactBytes() throws {
        let data = Data([0x3C, 0x68, 0x74, 0x6D, 0x6C, 0x3E, 0x0A, 0x0D, 0x00, 0xFF])
        let url = try TemplateStorage.write(name: "raw.html", data: data, in: directory)
        XCTAssertEqual(try Data(contentsOf: url), data)
    }

    func testWriteDataRejectsOversizedPayload() {
        let data = Data(repeating: 0x61, count: TemplateStorage.maxBytes + 1)
        XCTAssertThrowsError(try TemplateStorage.write(name: "big.html", data: data,
                                                       in: directory)) {
            XCTAssertEqual($0 as? TemplateStorage.Error,
                           .tooLarge(TemplateStorage.maxBytes + 1))
        }
    }

    func testWritePreservesExistingPermissions() throws {
        let url = directory.appendingPathComponent("panel.html")
        try "old".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o640],
                                              ofItemAtPath: url.path)

        try TemplateStorage.write("new", to: url)

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o640)
    }

    func testWriteRejectsOversizedHTML() {
        let html = String(repeating: "a", count: TemplateStorage.maxBytes + 1)
        XCTAssertThrowsError(try TemplateStorage.write(name: "big.html", html: html, in: directory)) {
            XCTAssertEqual($0 as? TemplateStorage.Error,
                           .tooLarge(TemplateStorage.maxBytes + 1))
        }
    }

    func testReadRejectsOversizedFile() throws {
        let url = directory.appendingPathComponent("big.html")
        try Data(repeating: 0x61, count: TemplateStorage.maxBytes + 1).write(to: url)

        XCTAssertThrowsError(try TemplateStorage.read(name: "big.html", in: directory)) {
            XCTAssertEqual($0 as? TemplateStorage.Error,
                           .tooLarge(TemplateStorage.maxBytes + 1))
        }
    }

    func testRejectsPathTraversal() {
        XCTAssertThrowsError(try TemplateStorage.read(name: "../escape.html", in: directory)) {
            XCTAssertTrue($0 is TemplateFilePolicy.Error)
        }
    }

    func testDeleteMissingFileThrowsNotFound() {
        XCTAssertThrowsError(try TemplateStorage.delete(name: "missing.html", in: directory)) {
            XCTAssertEqual($0 as? TemplateStorage.Error, .notFound("missing.html"))
        }
    }
}
