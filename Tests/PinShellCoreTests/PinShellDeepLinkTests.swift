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
            trustedCatalogURLs: [officialCatalog])
        XCTAssertEqual(request, .init(templateID: "gomoku", catalogURL: officialCatalog))
    }

    func testAcceptsLoopbackCatalogWhenTrusted() {
        let trusted = URL(string: "http://127.0.0.1:8000/library.json")!
        let request = PinShellDeepLink.installRequest(
            from: link(template: "todo", catalog: trusted.absoluteString),
            trustedCatalogURLs: [trusted])
        XCTAssertEqual(request, .init(templateID: "todo", catalogURL: trusted))
    }

    func testAcceptsAnyConfiguredTrustedCatalog() {
        let custom = URL(string: "https://team.example.com/library.json")!
        let request = PinShellDeepLink.installRequest(
            from: link(template: "note", catalog: custom.absoluteString),
            trustedCatalogURLs: [officialCatalog, custom])
        XCTAssertEqual(request, .init(templateID: "note", catalogURL: custom))
    }

    func testRejectsUnconfiguredCatalogWhenOtherSourcesAreTrusted() {
        let custom = URL(string: "https://team.example.com/library.json")!
        XCTAssertNil(PinShellDeepLink.installRequest(
            from: link(template: "note", catalog: custom.absoluteString),
            trustedCatalogURLs: [officialCatalog]))
    }

    func testRejectsDifferentDomain() {
        XCTAssertNil(PinShellDeepLink.installRequest(
            from: link(template: "gomoku",
                       catalog: "https://evil.example.com/library.json"),
            trustedCatalogURLs: [officialCatalog]))
    }

    func testRejectsDifferentPathOnSameHost() {
        XCTAssertNil(PinShellDeepLink.installRequest(
            from: link(template: "gomoku",
                       catalog: "https://pinshell.looplooptech.com/evil.json"),
            trustedCatalogURLs: [officialCatalog]))
    }

    func testRejectsMissingCatalog() {
        XCTAssertNil(PinShellDeepLink.installRequest(
            from: link(template: "gomoku", catalog: nil),
            trustedCatalogURLs: [officialCatalog]))
    }

    func testRejectsInvalidTemplateID() {
        for template in ["../todo", "GoMoku", "-evil", "", "a b"] {
            XCTAssertNil(PinShellDeepLink.installRequest(
                from: link(template: template),
                trustedCatalogURLs: [officialCatalog]), template)
        }
    }

    func testRejectsDuplicateParameters() {
        let url = URL(string: "pinshell://install?template=gomoku&template=todo&catalog=https%3A%2F%2Fpinshell.looplooptech.com%2Flibrary.json")!
        XCTAssertNil(PinShellDeepLink.installRequest(
            from: url, trustedCatalogURLs: [officialCatalog]))
    }

    func testRejectsNonHTTPSNonLoopbackCatalog() {
        let trusted = URL(string: "http://example.com/library.json")!
        XCTAssertNil(PinShellDeepLink.installRequest(
            from: link(template: "gomoku", catalog: trusted.absoluteString),
            trustedCatalogURLs: [trusted]))
    }

    func testRejectsWrongSchemeOrHost() {
        let wrongScheme = URL(string: "https://install?template=gomoku&catalog=https%3A%2F%2Fpinshell.looplooptech.com%2Flibrary.json")!
        let wrongHost = URL(string: "pinshell://open?template=gomoku&catalog=https%3A%2F%2Fpinshell.looplooptech.com%2Flibrary.json")!
        XCTAssertNil(PinShellDeepLink.installRequest(
            from: wrongScheme, trustedCatalogURLs: [officialCatalog]))
        XCTAssertNil(PinShellDeepLink.installRequest(
            from: wrongHost, trustedCatalogURLs: [officialCatalog]))
    }
}
