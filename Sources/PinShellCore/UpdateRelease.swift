import Foundation

/// GitHub Release 中的一个附件（只保留更新需要的字段）。
public struct ReleaseAsset: Decodable, Equatable, Sendable {
    public let name: String
    public let browserDownloadURL: URL
    public let size: Int64
    /// GitHub API 返回的 `sha256:<hex>`；较旧或未计算摘要的附件可能没有。
    public let digest: String?

    public init(name: String, browserDownloadURL: URL, size: Int64, digest: String? = nil) {
        self.name = name
        self.browserDownloadURL = browserDownloadURL
        self.size = size
        self.digest = digest
    }

    /// 去掉算法前缀后的 SHA-256 小写十六进制串；不是 sha256 摘要时返回 nil。
    public var sha256: String? {
        guard let digest, digest.lowercased().hasPrefix("sha256:") else { return nil }
        return String(digest.dropFirst("sha256:".count)).lowercased()
    }

    enum CodingKeys: String, CodingKey {
        case name, size, digest
        case browserDownloadURL = "browser_download_url"
    }
}

/// `GET /repos/{owner}/{repo}/releases/latest` 的响应（只保留更新需要的字段）。
public struct UpdateRelease: Decodable, Equatable, Sendable {
    public let tagName: String
    public let name: String?
    public let body: String?
    public let htmlURL: URL?
    public let assets: [ReleaseAsset]

    public init(tagName: String,
                name: String? = nil,
                body: String? = nil,
                htmlURL: URL? = nil,
                assets: [ReleaseAsset] = []) {
        self.tagName = tagName
        self.name = name
        self.body = body
        self.htmlURL = htmlURL
        self.assets = assets
    }

    /// 去掉 tag 的 "v" 前缀，用于展示与「跳过此版本」比对。
    public var versionLabel: String { VersionNumber.normalized(tagName) }

    /// 自动安装用的安装包：稳定文件名优先，其次带版本号的文件，最后任意 .pkg。
    /// 旧版本发布可能完全没有 pkg，此时返回 nil。
    public var pkgAsset: ReleaseAsset? {
        if let stable = assets.first(where: { $0.name == "PinShell.pkg" }) {
            return stable
        }
        let versioned = "PinShell-\(versionLabel)-mac-universal.pkg"
        if let exact = assets.first(where: { $0.name == versioned }) {
            return exact
        }
        return assets.first { $0.name.lowercased().hasSuffix(".pkg") }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name, body, assets
        case htmlURL = "html_url"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try container.decode(String.self, forKey: .tagName)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        htmlURL = try container.decodeIfPresent(URL.self, forKey: .htmlURL)
        assets = try container.decodeIfPresent([ReleaseAsset].self, forKey: .assets) ?? []
    }
}

/// 版本号比较：数字段逐段比较，非数字后缀忽略，缺位补 0。
public enum VersionNumber {
    /// 去掉前导 v/V（tag "v1.2.3" → "1.2.3"）。
    public static func normalized(_ version: String) -> String {
        String(version.drop(while: { $0 == "v" || $0 == "V" }))
    }

    /// "1.2.3" → [1,2,3]，非数字段按 0 处理（如 "1.0.0-beta1" → [1,0,0]），缺位补 0。
    public static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let pa = parse(a), pb = parse(b)
        for i in 0..<max(pa.count, pb.count) {
            let x = pa.count > i ? pa[i] : 0
            let y = pb.count > i ? pb[i] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    private static func parse(_ version: String) -> [Int] {
        normalized(version)
            .split(separator: ".")
            .map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }
}
