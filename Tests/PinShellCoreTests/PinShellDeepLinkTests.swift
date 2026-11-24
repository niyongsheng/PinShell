import XCTest
@testable import PinShellCore

final class PinShellDeepLinkTests: XCTestCase {
    private let officialCatalog = URL(string: "https://pinshell.looplooptech.com/library.json")!

    private func link(template: String,
                      catalog: String? = "https://pinshell.looplooptech.com/library.json") -> URL {
        var components = URLComponents()
        components.scheme = "pinshell"
        components.host = "install"
        var items: [URLQueryItem] = []
        if !template.isEmpty {
            items.append(URLQueryItem(name: "template", value: template))
        }
        if let catalog {
            items.append(URLQueryItem(name: "catalog", value: catalog))
        }
        components.queryItems = items
        return components.url!
    }

    func testAcceptsOfficialCatalogAndValidTemplate() {
        let request = PinShellDeepLink.installRequest(
            from: link(template: "gomoku"),
            trustedCatalogURL: officialCatalog)
        XCTAssertEqual(request, .init(templateID: "gomoku"))
    }

    func testAcceptsLoopbackCatalogWhenTrusted() {
        let trusted = URL(string: "http://127.0.0.1:8000/library.json")!
        let request = PinShellDeepLink.installRequest(
            from: link(template: "todo", catalog: trusted.absoluteString),
            trustedCatalogURL: trusted)
        XCTAssertEqual(request, .init(templateID: "todo"))
    }

    func testRejectsDifferentDomain() {
        XCTAssertNil(PinShellDeepLink.installRequest(
            from: link(template: "gomoku",
                       catalog: "https://evil.example.com/library.json"),
            trustedCatalogURL: officialCatalog))
    }

    func testRejectsDifferentPathOnSameHost() {
        XCTAssertNil(PinShellDeepLink.installRequest(
            from: link(template: "gomoku",
                       catalog: "https://pinshell.looplooptech.com/evil.json"),
            trustedCatalogURL: officialCatalog))
    }

    func testRejectsMissingCatalog() {
        XCTAssertNil(PinShellDeepLink.installRequest(
            from: link(template: "gomoku", catalog: nil),
            trustedCatalogURL: officialCatalog))
    }

    func testRejectsInvalidTemplateID() {
        for template in ["../todo", "GoMoku", "-evil", "", "a b"] {
            XCTAssertNil(PinShellDeepLink.installRequest(
                from: link(template: template),
                trustedCatalogURL: officialCatalog), template)
        }
    }

    func testRejectsDuplicateParameters() {
        let url = URL(string: "pinshell://install?template=gomoku&template=todo&catalog=https%3A%2F%2Fpinshell.looplooptech.com%2Flibrary.json")!
        XCTAssertNil(PinShellDeepLink.installRequest(
            from: url, trustedCatalogURL: officialCatalog))
    }

    func testRejectsNonHTTPSNonLoopbackCatalog() {
        let trusted = URL(string: "http://example.com/library.json")!
        XCTAssertNil(PinShellDeepLink.installRequest(
            from: link(template: "gomoku", catalog: trusted.absoluteString),
            trustedCatalogURL: trusted))
    }

    func testRejectsWrongSchemeOrHost() {
        let wrongScheme = URL(string: "https://install?template=gomoku&catalog=https%3A%2F%2Fpinshell.looplooptech.com%2Flibrary.json")!
        let wrongHost = URL(string: "pinshell://open?template=gomoku&catalog=https%3A%2F%2Fpinshell.looplooptech.com%2Flibrary.json")!
        XCTAssertNil(PinShellDeepLink.installRequest(
            from: wrongScheme, trustedCatalogURL: officialCatalog))
        XCTAssertNil(PinShellDeepLink.installRequest(
            from: wrongHost, trustedCatalogURL: officialCatalog))
    }
}
