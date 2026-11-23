import Foundation
import XCTest
@testable import PinShellCore

final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response,
                                cacheStoragePolicy: .notAllowed)
            if !data.isEmpty {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class TemplateCatalogClientTests: XCTestCase {
    private var cacheDirectory: URL!
    private var session: URLSession!
    private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
    private let catalogURL = URL(string: "https://example.com/PinShell/library.json")!

    override func setUpWithError() throws {
        cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PinShellCatalogCache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: cacheDirectory,
                                                withIntermediateDirectories: true)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: configuration)
        StubURLProtocol.handler = nil
    }

    override func tearDownWithError() throws {
        session.invalidateAndCancel()
        StubURLProtocol.handler = nil
        try? FileManager.default.removeItem(at: cacheDirectory)
    }

    private func client() -> TemplateCatalogClient {
        let date = fixedDate
        return TemplateCatalogClient(session: session,
                                     cacheDirectory: cacheDirectory,
                                     now: { date })
    }

    private func response(for request: URLRequest,
                          status: Int = 200,
                          headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!,
                        statusCode: status,
                        httpVersion: "HTTP/1.1",
                        headerFields: headers)!
    }

    func testFetch200WritesCache() async throws {
        let data = try TemplateLibraryFixtures.indexData()
        StubURLProtocol.handler = { request in
            (self.response(for: request, headers: ["ETag": "\"abc\""]), data)
        }

        let snapshot = try await client().fetch(catalogURL: catalogURL)
        XCTAssertEqual(snapshot.source, .network)
        XCTAssertEqual(snapshot.index.templates.first?.id, "todo")
        XCTAssertFalse(snapshot.isReadOnly)

        let files = try FileManager.default.contentsOfDirectory(
            at: cacheDirectory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.filter { $0.pathExtension == "json" }.count, 2)
    }

    func test304UsesCachedCatalog() async throws {
        let data = try TemplateLibraryFixtures.indexData()
        StubURLProtocol.handler = { request in
            (self.response(for: request, headers: ["ETag": "\"abc\""]), data)
        }
        _ = try await client().fetch(catalogURL: catalogURL)

        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "\"abc\"")
            return (self.response(for: request, status: 304), Data())
        }
        let snapshot = try await client().fetch(catalogURL: catalogURL)
        XCTAssertEqual(snapshot.source, .notModified)
        XCTAssertEqual(snapshot.index.templates.first?.id, "todo")
    }

    func testNetworkFailureFallsBackToCache() async throws {
        let data = try TemplateLibraryFixtures.indexData()
        StubURLProtocol.handler = { request in
            (self.response(for: request), data)
        }
        _ = try await client().fetch(catalogURL: catalogURL)

        StubURLProtocol.handler = { _ in
            throw URLError(.notConnectedToInternet)
        }
        let snapshot = try await client().fetch(catalogURL: catalogURL)
        XCTAssertEqual(snapshot.source, .cacheFallback)
        XCTAssertTrue(snapshot.isReadOnly)
    }

    func testOversizedCatalogIsRejected() async throws {
        StubURLProtocol.handler = { request in
            (self.response(for: request,
                           headers: ["Content-Length": "3000000"]), Data())
        }
        do {
            _ = try await client().fetch(catalogURL: catalogURL)
            XCTFail("expected tooLarge")
        } catch {
            guard case .some(.tooLarge) = error as? TemplateCatalogClientError else {
                return XCTFail("expected tooLarge, got \(error)")
            }
        }
    }

    func testUnsupportedSchemaIsRejected() async throws {
        var index = TemplateLibraryFixtures.index()
        index.schemaVersion = 2
        let data = try JSONEncoder().encode(index)
        StubURLProtocol.handler = { request in
            (self.response(for: request), data)
        }
        do {
            _ = try await client().fetch(catalogURL: catalogURL)
            XCTFail("expected catalogTooNew")
        } catch {
            XCTAssertEqual(error as? TemplateCatalogClientError, .catalogTooNew(2))
        }
    }

    func testInvalidJSONIsRejected() async throws {
        StubURLProtocol.handler = { request in
            (self.response(for: request), Data("{}".utf8))
        }
        do {
            _ = try await client().fetch(catalogURL: catalogURL)
            XCTFail("expected invalidCatalog")
        } catch {
            guard case .some(.invalidCatalog) = error as? TemplateCatalogClientError else {
                return XCTFail("expected invalidCatalog, got \(error)")
            }
        }
    }

    func testRejectsNonHTTPSRemoteCatalog() async {
        let url = URL(string: "http://example.com/library.json")!
        do {
            _ = try await client().fetch(catalogURL: url)
            XCTFail("expected invalidURL")
        } catch {
            XCTAssertEqual(error as? TemplateCatalogClientError, .invalidURL)
        }
    }

    func testDownloadPayloadResolvesRelativeURL() async throws {
        let payload = Data("<html><body>ok</body></html>".utf8)
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString,
                           "https://example.com/PinShell/templates/todo/1.0.0/todo.html")
            return (self.response(for: request), payload)
        }
        let data = try await client().downloadPayload(
            "templates/todo/1.0.0/todo.html",
            relativeTo: catalogURL)
        XCTAssertEqual(data, payload)
    }

    func testForceRefreshAddsCacheBustingQuery() async throws {
        let data = try TemplateLibraryFixtures.indexData()
        StubURLProtocol.handler = { request in
            XCTAssertTrue(request.url?.query?.contains("t=") == true)
            return (self.response(for: request), data)
        }
        let snapshot = try await client().fetch(catalogURL: catalogURL,
                                                forceRefresh: true)
        XCTAssertEqual(snapshot.source, .network)
    }
}
