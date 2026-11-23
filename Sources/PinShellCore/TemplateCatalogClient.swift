import Foundation

public struct TemplateCatalogSnapshot: Sendable, Equatable {
    public enum Source: String, Sendable, Equatable {
        case network
        case notModified
        /// 使用本地缓存；只允许浏览，不允许安装。
        case cacheFallback
    }

    public var index: TemplateLibraryIndex
    public var catalogURL: URL
    public var fetchedAt: Date
    public var source: Source

    public init(index: TemplateLibraryIndex, catalogURL: URL,
                fetchedAt: Date, source: Source) {
        self.index = index
        self.catalogURL = catalogURL
        self.fetchedAt = fetchedAt
        self.source = source
    }

    public var isReadOnly: Bool { source == .cacheFallback }
}

public enum TemplatePayloadDownloadError: Error, Equatable, CustomStringConvertible {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case tooLarge(Int)
    case empty

    public var description: String {
        switch self {
        case .invalidURL:
            return "invalid template payload URL"
        case .invalidResponse:
            return "invalid template payload response"
        case .httpStatus(let code):
            return "template download failed with HTTP \(code)"
        case .tooLarge(let bytes):
            return "template payload exceeds \(TemplateLibraryValidation.maxPayloadBytes) bytes (got \(bytes))"
        case .empty:
            return "template payload is empty"
        }
    }
}

public enum TemplateCatalogClientError: Error, Equatable, CustomStringConvertible {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case tooLarge(Int)
    case catalogTooNew(Int)
    case invalidCatalog(String)
    case noCachedCatalog

    public var description: String {
        switch self {
        case .invalidURL:
            return "invalid catalog URL"
        case .invalidResponse:
            return "invalid catalog response"
        case .httpStatus(let code):
            return "catalog request failed with HTTP \(code)"
        case .tooLarge(let bytes):
            return "catalog exceeds \(TemplateLibraryValidation.maxCatalogBytes) bytes (got \(bytes))"
        case .catalogTooNew(let version):
            return "catalog schemaVersion \(version) requires a newer PinShell"
        case .invalidCatalog(let message):
            return "invalid catalog: \(message)"
        case .noCachedCatalog:
            return "no cached catalog available"
        }
    }
}

/// 拉取官网 `library.json`，带 ETag/Last-Modified 缓存与离线回退。
public actor TemplateCatalogClient {
    private struct CacheMeta: Codable {
        var etag: String?
        var lastModified: String?
        var fetchedAt: Date?
        var catalogURL: String?

        init(etag: String? = nil, lastModified: String? = nil,
             fetchedAt: Date? = nil, catalogURL: String? = nil) {
            self.etag = etag
            self.lastModified = lastModified
            self.fetchedAt = fetchedAt
            self.catalogURL = catalogURL
        }
    }

    private let session: URLSession
    private let cacheDirectory: URL
    private let now: @Sendable () -> Date

    public init(session: URLSession = .shared,
                cacheDirectory: URL,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.session = session
        self.cacheDirectory = cacheDirectory
        self.now = now
    }

    public func fetch(catalogURL: URL,
                      forceRefresh: Bool = false) async throws -> TemplateCatalogSnapshot {
        guard TemplateLibraryValidation.isAllowedCatalogURL(catalogURL) else {
            throw TemplateCatalogClientError.invalidURL
        }

        let requestURL = forceRefresh ? Self.cacheBusted(catalogURL) : catalogURL
        var request = URLRequest(url: requestURL)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("PinShell/\(Self.appVersion)", forHTTPHeaderField: "User-Agent")

        let cache = loadCache(for: catalogURL)
        if !forceRefresh {
            if let etag = cache?.meta.etag {
                request.setValue(etag, forHTTPHeaderField: "If-None-Match")
            }
            if let lastModified = cache?.meta.lastModified {
                request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
            }
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw TemplateCatalogClientError.invalidResponse
            }

            if http.statusCode == 304 {
                guard let cached = cache?.data else {
                    throw TemplateCatalogClientError.noCachedCatalog
                }
                let index = try decodeAndValidate(cached)
                return TemplateCatalogSnapshot(
                    index: index,
                    catalogURL: catalogURL,
                    fetchedAt: cache?.meta.fetchedAt ?? now(),
                    source: .notModified
                )
            }

            guard http.statusCode == 200 else {
                throw TemplateCatalogClientError.httpStatus(http.statusCode)
            }
            try checkSize(contentLength: http.value(forHTTPHeaderField: "Content-Length"),
                          actual: data.count)
            let index = try decodeAndValidate(data)
            writeCache(data: data, catalogURL: catalogURL, response: http)
            return TemplateCatalogSnapshot(
                index: index,
                catalogURL: catalogURL,
                fetchedAt: now(),
                source: .network
            )
        } catch let error as TemplateCatalogClientError {
            if case .invalidURL = error { throw error }
            if case .noCachedCatalog = error { throw error }
            if case .catalogTooNew = error { throw error }
            if let cached = cache?.data {
                let index = try decodeAndValidate(cached)
                return TemplateCatalogSnapshot(
                    index: index,
                    catalogURL: catalogURL,
                    fetchedAt: cache?.meta.fetchedAt ?? now(),
                    source: .cacheFallback
                )
            }
            throw error
        } catch {
            if let cached = cache?.data {
                let index = try decodeAndValidate(cached)
                return TemplateCatalogSnapshot(
                    index: index,
                    catalogURL: catalogURL,
                    fetchedAt: cache?.meta.fetchedAt ?? now(),
                    source: .cacheFallback
                )
            }
            throw TemplateCatalogClientError.invalidCatalog(error.localizedDescription)
        }
    }

    /// 下载模板 HTML。URL 可相对 catalog URL；只允许 HTTPS 或 loopback HTTP。
    public func downloadPayload(_ urlString: String,
                                relativeTo catalogURL: URL) async throws -> Data {
        guard let url = URL(string: urlString, relativeTo: catalogURL)?.absoluteURL,
              TemplateLibraryValidation.isAllowedRemoteURL(url) else {
            throw TemplatePayloadDownloadError.invalidURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("PinShell/\(Self.appVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TemplatePayloadDownloadError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw TemplatePayloadDownloadError.httpStatus(http.statusCode)
        }
        if let value = http.value(forHTTPHeaderField: "Content-Length"),
           let expected = Int(value),
           expected > TemplateLibraryValidation.maxPayloadBytes {
            throw TemplatePayloadDownloadError.tooLarge(expected)
        }
        guard data.count <= TemplateLibraryValidation.maxPayloadBytes else {
            throw TemplatePayloadDownloadError.tooLarge(data.count)
        }
        guard !data.isEmpty else {
            throw TemplatePayloadDownloadError.empty
        }
        return data
    }

    // MARK: - 解码

    private func decodeAndValidate(_ data: Data) throws -> TemplateLibraryIndex {
        try checkSize(contentLength: nil, actual: data.count)
        let index: TemplateLibraryIndex
        do {
            index = try JSONDecoder().decode(TemplateLibraryIndex.self, from: data)
        } catch {
            throw TemplateCatalogClientError.invalidCatalog(error.localizedDescription)
        }
        if index.schemaVersion > TemplateLibraryValidation.supportedSchemaVersion {
            throw TemplateCatalogClientError.catalogTooNew(index.schemaVersion)
        }
        do {
            try TemplateLibraryValidation.validate(index,
                                                   allowAbsolutePayloadURL: true)
        } catch let error as TemplateLibraryValidationError {
            if case .unsupportedSchema(let version) = error {
                throw TemplateCatalogClientError.catalogTooNew(version)
            }
            throw TemplateCatalogClientError.invalidCatalog(error.description)
        }
        return index
    }

    private func checkSize(contentLength: String?, actual: Int) throws {
        if let contentLength, let expected = Int(contentLength),
           expected > TemplateLibraryValidation.maxCatalogBytes {
            throw TemplateCatalogClientError.tooLarge(expected)
        }
        guard actual <= TemplateLibraryValidation.maxCatalogBytes else {
            throw TemplateCatalogClientError.tooLarge(actual)
        }
    }

    // MARK: - 缓存

    private func cacheKey(for catalogURL: URL) -> String {
        FileDigest.sha256(of: Data(catalogURL.absoluteString.utf8))
    }

    private func cachePaths(for catalogURL: URL) -> (data: URL, meta: URL) {
        let key = cacheKey(for: catalogURL)
        return (
            cacheDirectory.appendingPathComponent("\(key).json"),
            cacheDirectory.appendingPathComponent("\(key).meta.json")
        )
    }

    private func loadCache(for catalogURL: URL) -> (data: Data, meta: CacheMeta)? {
        let paths = cachePaths(for: catalogURL)
        guard let data = try? Data(contentsOf: paths.data) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let meta = (try? decoder.decode(CacheMeta.self,
                                        from: Data(contentsOf: paths.meta)))
            ?? CacheMeta()
        return (data, meta)
    }

    private func writeCache(data: Data, catalogURL: URL,
                            response: HTTPURLResponse) {
        let paths = cachePaths(for: catalogURL)
        try? FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
        try? data.write(to: paths.data, options: .atomic)

        let meta = CacheMeta(
            etag: response.value(forHTTPHeaderField: "ETag"),
            lastModified: response.value(forHTTPHeaderField: "Last-Modified"),
            fetchedAt: now(),
            catalogURL: catalogURL.absoluteString
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let encoded = try? encoder.encode(meta) {
            try? encoded.write(to: paths.meta, options: .atomic)
        }
    }

    // MARK: - Helpers

    private static func cacheBusted(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970))))
        components.queryItems = items
        return components.url ?? url
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0"
    }
}
