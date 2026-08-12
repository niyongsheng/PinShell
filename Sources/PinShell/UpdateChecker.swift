import Foundation

/// 从 GitHub Releases 检查新版本（无第三方依赖，纯 URLSession）。
/// 仅做检测与提示，不做自动下载/安装（应用为 ad-hoc 签名）。
enum UpdateChecker {
    /// 与 git remote 对应的仓库
    static let repo = "niyongsheng/PinShell"
    static let latestAPIURL = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
    /// 浏览器兜底跳转的发布页
    static let releasesPageURL = URL(string: "https://github.com/\(repo)/releases")!

    // MARK: - 检查策略常量

    /// 自动检查节流：距上次检查超过该时长才再查
    static let checkInterval: TimeInterval = 24 * 3600
    /// 启动后延迟自动检查的时长（不打断首次使用）
    static let autoCheckDelay: TimeInterval = 5
    /// 请求超时（国内访问 GitHub 可能慢）
    static let requestTimeout: TimeInterval = 15

    /// 当前安装版本（由 CI 打 tag 时写入 Info.plist）
    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    enum Result {
        case upToDate
        case updateAvailable(ReleaseInfo)
        case failed(String)
    }

    struct ReleaseInfo: Decodable {
        let tagName: String
        let name: String?
        let body: String?
        let htmlURL: URL?

        /// 去掉 tag 的 "v" 前缀，用于展示与"跳过此版本"比对
        var versionLabel: String { UpdateChecker.stripVPrefix(tagName) }

        /// 展示用摘要：name 优先，body 截断到 limit；都没有则用兜底文案
        func excerpt(limit: Int = 500) -> String {
            if let name, !name.isEmpty { return name }
            guard let body else {
                return String(format: NSLocalizedString("update.availableMessage", comment: ""), versionLabel)
            }
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.count > limit ? String(trimmed.prefix(limit)) + "…" : trimmed
        }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name, body
            case htmlURL = "html_url"
        }
    }

    /// 完整检查：拉取最新 release，与当前版本及用户跳过的版本比较。
    /// 需在异步上下文调用，结束后由调用方在合适线程展示结果。
    static func check() async -> Result {
        var request = URLRequest(url: latestAPIURL)
        // GitHub API 强制要求 User-Agent，缺失返回 403
        request.setValue("PinShell/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = requestTimeout
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                return .failed(String(format: NSLocalizedString("update.httpError", comment: ""), code))
            }
            let release = try JSONDecoder().decode(ReleaseInfo.self, from: data)
            let latest = release.versionLabel
            if compare(latest, currentVersion) != .orderedDescending {
                return .upToDate
            }
            if latest == AppState.skippedVersion {
                return .upToDate   // 用户已跳过该版本，不再提醒
            }
            return .updateAvailable(release)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// 版本号比较："1.2.3" → [1,2,3]，非数字段按 0 处理（如 "1.0.0-beta1" → [1,0,0]），缺位补 0
    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let pa = parse(a), pb = parse(b)
        for i in 0..<max(pa.count, pb.count) {
            let x = pa.count > i ? pa[i] : 0
            let y = pb.count > i ? pb[i] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    /// 去掉前导 v/V 前缀（tag "v1.2.3" → "1.2.3"）
    private static func stripVPrefix(_ s: String) -> String {
        String(s.drop(while: { $0 == "v" || $0 == "V" }))
    }

    private static func parse(_ version: String) -> [Int] {
        stripVPrefix(version)
            .split(separator: ".")
            .map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }
}
