import XCTest
@testable import PinShellCore

final class TemplateCatalogURLTests: XCTestCase {
    func testKeepsExplicitCatalogFileURL() throws {
        let url = try TemplateCatalogURL.normalize(
            "https://example.com/library.json").get()
        XCTAssertEqual(url.absoluteString, "https://example.com/library.json")
    }

    func testCompletesSiteRoot() throws {
        XCTAssertEqual(
            try TemplateCatalogURL.normalize("https://example.com").get().absoluteString,
            "https://example.com/library.json")
        XCTAssertEqual(
            try TemplateCatalogURL.normalize("https://example.com/").get().absoluteString,
            "https://example.com/library.json")
    }

    func testCompletesDirectoryURL() throws {
        XCTAssertEqual(
            try TemplateCatalogURL.normalize("https://example.com/team/").get().absoluteString,
            "https://example.com/team/library.json")
    }

    func testAddsHTTPSForBareHost() throws {
        XCTAssertEqual(
            try TemplateCatalogURL.normalize("example.com").get().absoluteString,
            "https://example.com/library.json")
    }

    func testLowercasesSchemeAndHost() throws {
        XCTAssertEqual(
            try TemplateCatalogURL.normalize("HTTPS://EXAMPLE.com").get().absoluteString,
            "https://example.com/library.json")
    }

    func testAllowsLoopbackHTTP() throws {
        XCTAssertEqual(
            try TemplateCatalogURL.normalize("http://127.0.0.1:8000").get().absoluteString,
            "http://127.0.0.1:8000/library.json")
        XCTAssertEqual(
            try TemplateCatalogURL.normalize("http://localhost:8000/library.json")
                .get().absoluteString,
            "http://localhost:8000/library.json")
    }

    func testRejectsInsecureRemoteHTTP() {
        XCTAssertEqual(TemplateCatalogURL.normalize("http://example.com/library.json"),
                       .failure(.insecure))
    }

    func testRejectsUnsupportedScheme() {
        XCTAssertEqual(TemplateCatalogURL.normalize("ftp://example.com/library.json"),
                       .failure(.insecure))
    }

    func testRejectsEmptyInput() {
        XCTAssertEqual(TemplateCatalogURL.normalize("   \n"), .failure(.empty))
    }

    func testRejectsQueryFragmentAndUserInfo() {
        for raw in [
            "https://example.com/library.json?token=1",
            "https://example.com/library.json#section",
            "https://user:pass@example.com/library.json",
        ] {
            XCTAssertEqual(TemplateCatalogURL.normalize(raw), .failure(.invalid), raw)
        }
    }

    func testRejectsMalformedURL() {
        XCTAssertEqual(TemplateCatalogURL.normalize("https://"), .failure(.invalid))
    }
}
