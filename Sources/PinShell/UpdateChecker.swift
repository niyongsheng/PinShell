import Foundation
import PinShellCore

/// 从 GitHub Releases 检查新版本（无第三方依赖，纯 URLSession）。
/// 检测与提示、下载安装包交给 UpdateInstaller；不做原地替换（应用为 ad-hoc 签名）。
enum UpdateChecker {
    /// 与 git remote 对应的仓库
    static let repo = "niyongsheng/PinShell"
    static let latestAPIURL = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
    /// 网页端 latest 入口：302 跳到最新 tag 页。不走 API，不受匿名请求限流影响
    /// （GitHub 匿名额度仅 60 次/小时，共享出口 IP 很容易被耗尽而返回 403）。
    static let latestWebURL = URL(string: "https://github.com/\(repo)/releases/latest")!
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

    typealias ReleaseInfo = UpdateRelease

    enum Result {
        case upToDate
        case updateAvailable(ReleaseInfo)
        case failed(String)
    }

    /// 完整检查：先通过网页重定向取最新 tag，与当前版本及用户跳过的版本比较；
    /// 有新版本时才尝试用 API 补充更新说明、安装包大小与 sha256。
    /// 需在异步上下文调用，结束后由调用方在合适线程展示结果。
    static func check() async -> Result {
        do {
            let tag = try await latestTag()
            let fallback = ReleaseInfo.webFallback(tagName: tag, repository: repo)
            // 无新版本或用户已跳过时直接结束，不再消耗 API 额度
            guard case .updateAvailable = decide(fallback) else { return .upToDate }
            // API 被限流（403）或超时时静默降级，不影响「发现新版本」
            if let release = try? await fetchLatestRelease(), release.versionLabel == fallback.versionLabel {
                return .updateAvailable(release)
            }
            return .updateAvailable(fallback)
        } catch {
            // 网页端点异常时保留旧的 API 检查路径
            do {
                return decide(try await fetchLatestRelease())
            } catch {
                return .failed(error.localizedDescription)
            }
        }
    }

    /// 通过 `releases/latest` 的 302 Location 读取最新 tag，不下载 tag 页面内容。
    private static func latestTag() async throws -> String {
        var request = URLRequest(url: latestWebURL)
        // 重定向被拦下，GET 不会下载 tag 页面；比 HEAD 对代理/中间盒更兼容
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = requestTimeout
        request.setValue("PinShell/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (_, response) = try await URLSession.shared.data(for: request, delegate: RedirectStopper())
        guard let http = response as? HTTPURLResponse,
              let location = http.value(forHTTPHeaderField: "Location"),
              let target = URL(string: location, relativeTo: latestWebURL),
              let tag = ReleaseTag.fromReleaseURL(target) else {
            throw URLError(.badServerResponse)
        }
        return tag
    }

    /// 拉取最新 release（含更新说明、附件大小与 sha256）。
    private static func fetchLatestRelease() async throws -> ReleaseInfo {
        var request = URLRequest(url: latestAPIURL)
        // GitHub API 强制要求 User-Agent，缺失返回 403
        request.setValue("PinShell/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = requestTimeout
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            // 本地化文案占位符是 %@，必须传对象；直接传 Int 会被当指针解引用而崩溃
            throw UpdateCheckError.http(code)
        }
        return try JSONDecoder().decode(ReleaseInfo.self, from: data)
    }

    /// 与当前版本、用户跳过版本比较。
    private static func decide(_ release: ReleaseInfo) -> Result {
        let latest = release.versionLabel
        if VersionNumber.compare(latest, currentVersion) != .orderedDescending {
            return .upToDate
        }
        if latest == AppState.skippedVersion {
            return .upToDate   // 用户已跳过该版本，不再提醒
        }
        return .updateAvailable(release)
    }

    private enum UpdateCheckError: LocalizedError {
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .http(let code):
                return String(format: NSLocalizedString("update.httpError", comment: ""), String(code))
            }
        }
    }

    /// 只保留 302 响应读取 Location，不跟随跳转。
    private final class RedirectStopper: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession,
                        task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}

extension UpdateRelease {
    /// 展示用摘要：优先 release body，其次 name；截断到 limit，都没有则用兜底文案。
    func excerpt(limit: Int = 500) -> String {
        let text = (body ?? name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return String(format: NSLocalizedString("update.availableMessage", comment: ""), versionLabel)
        }
        return text.count > limit ? String(text.prefix(limit)) + "…" : text
    }
}
