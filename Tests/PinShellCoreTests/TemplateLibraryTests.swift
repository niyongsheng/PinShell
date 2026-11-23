import XCTest
@testable import PinShellCore

final class TemplateLibraryModelsTests: XCTestCase {
    func testDecodesCatalogAndLocalizesMetadata() throws {
        let data = try TemplateLibraryFixtures.indexData()
        let index = try JSONDecoder().decode(TemplateLibraryIndex.self, from: data)
        XCTAssertEqual(index.schemaVersion, 1)
        XCTAssertEqual(index.templates.count, 1)

        let entry = try XCTUnwrap(index.template(id: "todo"))
        XCTAssertEqual(entry.localizedName(preferredLanguages: ["zh-CN"]), "待办事项")
        XCTAssertEqual(entry.localizedName(preferredLanguages: ["en-US"]), "Todo List")
        XCTAssertEqual(entry.localizedName(preferredLanguages: ["fr"]), "Todo List")
        XCTAssertEqual(entry.pageURLString(preferredLanguages: ["zh-CN"]), "templates/todo/")
        XCTAssertEqual(entry.pageURLString(preferredLanguages: ["en"]), "en/templates/todo/")
        XCTAssertEqual(entry.changelogEntries.first?.version, "1.0.0")
        XCTAssertTrue(entry.hasCurrentChangelog)
    }

    func testUnknownFieldsAreIgnored() throws {
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: TemplateLibraryFixtures.indexData())
                as? [String: Any]
        )
        json["futureField"] = ["anything": true]
        var templates = try XCTUnwrap(json["templates"] as? [[String: Any]])
        templates[0]["futureTemplateField"] = 42
        json["templates"] = templates

        let data = try JSONSerialization.data(withJSONObject: json)
        XCTAssertNoThrow(try JSONDecoder().decode(TemplateLibraryIndex.self, from: data))
    }

    func testChangelogSortsNewestFirst() {
        var entry = TemplateLibraryFixtures.entry(version: "1.2.0")
        entry.changelog?["1.1.0"] = TemplateLibraryChangelogEntry(
            date: "2026-10-01", notes: ["zh-Hans": "上一版", "en": "Previous"])
        entry.changelog?["1.0.0"] = TemplateLibraryChangelogEntry(
            date: "2026-09-01", notes: ["zh-Hans": "首版", "en": "First"])
        XCTAssertEqual(entry.changelogEntries.map(\.version), ["1.2.0", "1.1.0", "1.0.0"])
    }
}

final class TemplateLibraryValidationTests: XCTestCase {
    func testValidCatalogPasses() throws {
        XCTAssertNoThrow(try TemplateLibraryValidation.validate(TemplateLibraryFixtures.index()))
    }

    func testRejectsUnsupportedSchema() {
        var index = TemplateLibraryFixtures.index()
        index.schemaVersion = 2
        XCTAssertThrowsError(try TemplateLibraryValidation.validate(index)) {
            XCTAssertEqual($0 as? TemplateLibraryValidationError, .unsupportedSchema(2))
        }
    }

    func testRejectsDuplicateIDs() {
        var index = TemplateLibraryFixtures.index()
        index.templates.append(TemplateLibraryFixtures.entry())
        XCTAssertThrowsError(try TemplateLibraryValidation.validate(index)) {
            XCTAssertEqual($0 as? TemplateLibraryValidationError, .duplicateID("todo"))
        }
    }

    func testRejectsFileMismatch() {
        var entry = TemplateLibraryFixtures.entry()
        entry.file = "other.html"
        entry.payload.fileName = "other.html"
        XCTAssertThrowsError(try TemplateLibraryValidation.validate(entry)) {
            XCTAssertEqual($0 as? TemplateLibraryValidationError,
                           .fileMismatch(id: "todo", file: "other.html"))
        }
    }

    func testRejectsInvalidVersionAndSHA() {
        var entry = TemplateLibraryFixtures.entry()
        entry.version = "1.0"
        XCTAssertThrowsError(try TemplateLibraryValidation.validate(entry)) {
            XCTAssertEqual($0 as? TemplateLibraryValidationError, .invalidVersion("1.0"))
        }

        entry = TemplateLibraryFixtures.entry()
        entry.payload.sha256 = "not-a-hash"
        XCTAssertThrowsError(try TemplateLibraryValidation.validate(entry)) {
            XCTAssertEqual($0 as? TemplateLibraryValidationError, .invalidSHA256("not-a-hash"))
        }
    }

    func testRejectsTraversalPayloadURL() {
        var entry = TemplateLibraryFixtures.entry()
        entry.payload.url = "../escape.html"
        XCTAssertThrowsError(try TemplateLibraryValidation.validate(entry)) {
            XCTAssertEqual($0 as? TemplateLibraryValidationError,
                           .invalidPayloadURL("../escape.html"))
        }
    }

    func testAbsolutePayloadURLRequiresExplicitPermission() {
        var entry = TemplateLibraryFixtures.entry()
        entry.payload.url = "https://example.com/todo.html"
        XCTAssertThrowsError(try TemplateLibraryValidation.validate(entry))
        XCTAssertNoThrow(try TemplateLibraryValidation.validate(
            entry, allowAbsolutePayloadURL: true))
    }

    func testRejectsMissingCurrentChangelog() {
        var entry = TemplateLibraryFixtures.entry()
        entry.changelog = [
            "0.9.0": TemplateLibraryChangelogEntry(
                date: "2026-01-01",
                notes: ["zh-Hans": "旧版", "en": "Old"])
        ]
        XCTAssertThrowsError(try TemplateLibraryValidation.validate(entry)) {
            XCTAssertEqual($0 as? TemplateLibraryValidationError,
                           .missingChangelog("todo"))
        }
    }

    func testRejectsUnknownCategory() {
        var entry = TemplateLibraryFixtures.entry()
        entry.category = "unknown"
        let categories: Set<String> = ["productivity"]
        XCTAssertThrowsError(try TemplateLibraryValidation.validate(
            entry, categories: categories)) {
            XCTAssertEqual($0 as? TemplateLibraryValidationError,
                           .invalidCategory("unknown"))
        }
    }

    func testRejectsEmptyLocalization() {
        var entry = TemplateLibraryFixtures.entry()
        entry.languages?["en"] = TemplateLibraryLocalization(name: "", description: "x")
        XCTAssertThrowsError(try TemplateLibraryValidation.validate(entry)) {
            XCTAssertEqual($0 as? TemplateLibraryValidationError,
                           .emptyLocalization(language: "en", field: "name"))
        }
    }

    func testRejectsInvalidPreview() {
        var entry = TemplateLibraryFixtures.entry()
        entry.preview?.width = 10
        XCTAssertThrowsError(try TemplateLibraryValidation.validate(entry)) {
            XCTAssertEqual($0 as? TemplateLibraryValidationError, .invalidPreview("todo"))
        }
    }

    func testSafePathAndURLHelpers() {
        XCTAssertTrue(TemplateLibraryValidation.isSafeRelativePath("templates/todo/1.0.0/todo.html"))
        XCTAssertFalse(TemplateLibraryValidation.isSafeRelativePath("../escape.html"))
        XCTAssertFalse(TemplateLibraryValidation.isSafeRelativePath("https://example.com/x"))
        XCTAssertTrue(TemplateLibraryValidation.isAllowedPayloadURL(
            "https://example.com/x", allowAbsoluteHTTPS: true))
        XCTAssertTrue(TemplateLibraryValidation.isAllowedCatalogURL(
            URL(string: "http://127.0.0.1:8000/library.json")!))
        XCTAssertFalse(TemplateLibraryValidation.isAllowedCatalogURL(
            URL(string: "http://example.com/library.json")!))
    }
}

final class TemplateUpdateEvaluatorTests: XCTestCase {
    private let appVersion = "1.5.0"

    func testNotInstalled() {
        let result = TemplateLibraryEvaluator.evaluate(
            entry: TemplateLibraryFixtures.entry(),
            record: nil, localSHA256: nil, appVersion: appVersion)
        XCTAssertEqual(result.installState, .notInstalled)
        XCTAssertTrue(result.updateAvailable)
        XCTAssertFalse(result.isEdited)
    }

    func testInstalledLatest() {
        let result = TemplateLibraryEvaluator.evaluate(
            entry: TemplateLibraryFixtures.entry(),
            record: .init(version: "1.0.0", sha256: TemplateLibraryFixtures.shaA),
            localSHA256: TemplateLibraryFixtures.shaA,
            appVersion: appVersion)
        XCTAssertEqual(result.installState, .installed)
        XCTAssertEqual(result.installedVersion, "1.0.0")
        XCTAssertFalse(result.updateAvailable)
        XCTAssertFalse(result.isEdited)
    }

    func testEditedLocalCopy() {
        let result = TemplateLibraryEvaluator.evaluate(
            entry: TemplateLibraryFixtures.entry(),
            record: .init(version: "1.0.0", sha256: TemplateLibraryFixtures.shaA),
            localSHA256: TemplateLibraryFixtures.shaB,
            appVersion: appVersion)
        XCTAssertEqual(result.installState, .installed)
        XCTAssertTrue(result.isEdited)
        XCTAssertFalse(result.updateAvailable)
    }

    func testUpdateAvailable() {
        let remote = TemplateLibraryFixtures.entry(version: "1.1.0")
        let result = TemplateLibraryEvaluator.evaluate(
            entry: remote,
            record: .init(version: "1.0.0", sha256: TemplateLibraryFixtures.shaA),
            localSHA256: TemplateLibraryFixtures.shaA,
            appVersion: appVersion)
        XCTAssertTrue(result.updateAvailable)
        XCTAssertFalse(result.isRepair)
    }

    func testSameVersionRepair() {
        let remote = TemplateLibraryFixtures.entry(sha256: TemplateLibraryFixtures.shaB)
        let result = TemplateLibraryEvaluator.evaluate(
            entry: remote,
            record: .init(version: "1.0.0", sha256: TemplateLibraryFixtures.shaA),
            localSHA256: TemplateLibraryFixtures.shaA,
            appVersion: appVersion)
        XCTAssertTrue(result.updateAvailable)
        XCTAssertTrue(result.isRepair)
    }

    func testIgnoreSuppressesUpdate() {
        let remote = TemplateLibraryFixtures.entry(version: "1.1.0")
        let result = TemplateLibraryEvaluator.evaluate(
            entry: remote,
            record: .init(version: "1.0.0", sha256: TemplateLibraryFixtures.shaA),
            localSHA256: TemplateLibraryFixtures.shaA,
            appVersion: appVersion,
            ignoredVersion: "1.1.0")
        XCTAssertTrue(result.isIgnored)
        XCTAssertFalse(result.updateAvailable)
    }

    func testOlderIgnoreDoesNotSuppressNewerUpdate() {
        let remote = TemplateLibraryFixtures.entry(version: "1.1.0")
        let result = TemplateLibraryEvaluator.evaluate(
            entry: remote,
            record: .init(version: "1.0.0", sha256: TemplateLibraryFixtures.shaA),
            localSHA256: TemplateLibraryFixtures.shaA,
            appVersion: appVersion,
            ignoredVersion: "1.0.0")
        XCTAssertFalse(result.isIgnored)
        XCTAssertTrue(result.updateAvailable)
    }

    func testNoDowngrade() {
        let remote = TemplateLibraryFixtures.entry(version: "0.9.0")
        let result = TemplateLibraryEvaluator.evaluate(
            entry: remote,
            record: .init(version: "1.0.0", sha256: TemplateLibraryFixtures.shaA),
            localSHA256: TemplateLibraryFixtures.shaA,
            appVersion: appVersion)
        XCTAssertFalse(result.updateAvailable)
    }

    func testNeedsNewerApp() {
        let remote = TemplateLibraryFixtures.entry(minAppVersion: "99.0.0")
        let result = TemplateLibraryEvaluator.evaluate(
            entry: remote,
            record: nil, localSHA256: nil, appVersion: appVersion)
        XCTAssertTrue(result.needsNewerApp)
        XCTAssertFalse(result.updateAvailable)
    }

    func testUnmanagedLocalFile() {
        let result = TemplateLibraryEvaluator.evaluate(
            entry: TemplateLibraryFixtures.entry(),
            record: nil, localSHA256: TemplateLibraryFixtures.shaB,
            appVersion: appVersion)
        XCTAssertEqual(result.installState, .unmanagedLocal)
        XCTAssertFalse(result.updateAvailable)
    }

    func testMissingInstalledFileBecomesInstallable() {
        let result = TemplateLibraryEvaluator.evaluate(
            entry: TemplateLibraryFixtures.entry(),
            record: .init(version: "1.0.0", sha256: TemplateLibraryFixtures.shaA),
            localSHA256: nil,
            appVersion: appVersion)
        XCTAssertEqual(result.installState, .notInstalled)
        XCTAssertTrue(result.updateAvailable)
    }
}
