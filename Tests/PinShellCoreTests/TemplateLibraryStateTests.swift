import XCTest
@testable import PinShellCore

final class TemplateLibraryStateTests: XCTestCase {
    private var directory: URL!
    private var store: TemplateLibraryStateStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PinShellLibraryState-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        store = TemplateLibraryStateStore(
            url: directory.appendingPathComponent("template-library.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testMissingFileLoadsEmptyState() throws {
        XCTAssertEqual(try store.load(), .empty)
    }

    func testRoundTrip() throws {
        var state = TemplateLibraryState()
        state.installed["todo"] = InstalledTemplateRecord(
            version: "1.0.0",
            sha256: TemplateLibraryFixtures.shaA,
            installedAt: Date(timeIntervalSince1970: 1_700_000_000),
            sourceCatalog: "https://example.com/library.json")
        state.ignored["gomoku"] = "1.1.0"
        try store.save(state)

        let loaded = try store.load()
        XCTAssertEqual(loaded.installed["todo"]?.version, "1.0.0")
        XCTAssertEqual(loaded.installed["todo"]?.sha256, TemplateLibraryFixtures.shaA)
        XCTAssertEqual(loaded.ignored["gomoku"], "1.1.0")
        XCTAssertEqual(loaded.installed["todo"]?.installedAt?.timeIntervalSince1970,
                       1_700_000_000)
    }

    func testCorruptFileIsQuarantined() throws {
        try Data("{not json".utf8).write(to: store.url)
        XCTAssertEqual(try store.load(), .empty)
        let backups = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.contains(".corrupt-") }
        XCTAssertEqual(backups.count, 1)
    }

    func testFutureSchemaIsPreservedAndRejected() throws {
        let future = """
        {"schemaVersion": 2, "installed": {}, "ignored": {}}
        """
        try Data(future.utf8).write(to: store.url)
        XCTAssertThrowsError(try store.load()) {
            XCTAssertEqual($0 as? TemplateLibraryStateError, .unsupportedSchema(2))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url.path))
    }

    func testSaveCreatesParentDirectoryAndRestrictsPermissions() throws {
        let nested = directory.appendingPathComponent("nested/dir/template-library.json")
        let nestedStore = TemplateLibraryStateStore(url: nested)
        try nestedStore.save(.empty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.path))

        let attributes = try FileManager.default.attributesOfItem(atPath: nested.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
}
