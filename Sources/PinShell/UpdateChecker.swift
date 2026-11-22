import Foundation
import PinShellCore

/// 从 GitHub Releases 检查新版本（无第三方依赖，纯 URLSession）。
/// 检测与提示、下载安装包交给 UpdateInstaller；不做原地替换（应用为 ad-hoc 签名）。
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

    typealias ReleaseInfo = UpdateRelease

    enum Result {
        case upToDate
        case updateAvailable(ReleaseInfo)
        case failed(String)
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
                // 本地化文案占位符是 %@，必须传对象；直接传 Int 会被当指针解引用而崩溃
                return .failed(String(format: NSLocalizedString("update.httpError", comment: ""), String(code)))
            }
            let release = try JSONDecoder().decode(ReleaseInfo.self, from: data)
            let latest = release.versionLabel
            if VersionNumber.compare(latest, currentVersion) != .orderedDescending {
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
