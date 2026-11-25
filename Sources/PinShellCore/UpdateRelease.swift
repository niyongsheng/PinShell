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

extension UpdateRelease {
    /// API 不可用（如未认证请求被限流）时按 tag 构造降级信息：
    /// tag 页链接 + release 中的稳定文件名安装包。没有大小与摘要，下载时跳过校验。
    /// 稳定链接始终指向最新 release，与刚探测到的 tag 一致。
    public static func webFallback(tagName: String, repository: String) -> UpdateRelease {
        let base = "https://github.com/\(repository)/releases"
        return UpdateRelease(tagName: tagName,
                             name: nil,   // 无更新说明，更新弹窗会使用本地化兜底文案
                             body: nil,
                             htmlURL: URL(string: "\(base)/tag/\(tagName)"),
                             assets: [ReleaseAsset(name: "PinShell.pkg",
                                                   browserDownloadURL: URL(string: "\(base)/latest/download/PinShell.pkg")!,
                                                   size: 0)])
    }
}

/// 从 GitHub release 页面 URL 中提取 tag（`.../releases/tag/v1.2.3` → `v1.2.3`）。
public enum ReleaseTag {
    public static func fromReleaseURL(_ url: URL) -> String? {
        let components = url.pathComponents
        guard components.count >= 3, components[components.count - 2] == "tag" else { return nil }
        let tag = components[components.count - 1]
        return tag.isEmpty || tag == "/" ? nil : tag
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
