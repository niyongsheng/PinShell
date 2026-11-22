import AppKit
import CryptoKit
import PinShellCore

/// 半自动更新：下载 Release 中的 pkg → 可选 SHA-256 校验 → 交给系统 Installer。
/// 应用没有 Developer ID 签名，因此不做原地替换；安装与管理员授权由 Installer 完成。
@MainActor
final class UpdateInstaller {
    enum InstallError: LocalizedError {
        case packageUnavailable
        case checksumMismatch
        case openInstallerFailed

        var errorDescription: String? {
            switch self {
            case .packageUnavailable:
                return NSLocalizedString("update.packageUnavailable", comment: "")
            case .checksumMismatch:
                return NSLocalizedString("update.checksumMismatch", comment: "")
            case .openInstallerFailed:
                return NSLocalizedString("update.openInstallerFailed", comment: "")
            }
        }
    }

    private var progressWindow: UpdateProgressWindowController?
    private var downloader: UpdateDownloader?
    private(set) var isInstalling = false

    /// 下载并打开安装器。用户取消时抛出 CancellationError。
    func install(_ release: UpdateChecker.ReleaseInfo) async throws {
        guard !isInstalling else { return }
        guard let asset = release.pkgAsset else { throw InstallError.packageUnavailable }

        isInstalling = true
        defer {
            isInstalling = false
            progressWindow?.close()
            progressWindow = nil
            downloader = nil
        }

        let window = UpdateProgressWindowController(version: release.versionLabel)
        progressWindow = window
        let downloader = UpdateDownloader()
        self.downloader = downloader
        window.onCancel = { [weak downloader] in downloader?.cancel() }
        window.show()

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("PinShell-\(release.versionLabel).pkg")
        let file = try await downloader.download(from: asset.browserDownloadURL,
                                                 expectedSize: asset.size,
                                                 to: destination) { received, total in
            window.update(received: received, total: total)
        }
        try Task.checkCancellation()

        // GitHub API 会为较新的附件返回 sha256 digest；没有时跳过校验。
        if let expected = asset.sha256 {
            window.setPhase(NSLocalizedString("update.verifying", comment: ""))
            let actual = try await Task.detached(priority: .userInitiated) {
                try FileDigest.sha256(of: file)
            }.value
            guard actual == expected else { throw InstallError.checksumMismatch }
        }
        try Task.checkCancellation()

        window.setPhase(NSLocalizedString("update.openingInstaller", comment: ""))
        guard NSWorkspace.shared.open(file) else { throw InstallError.openInstallerFailed }
    }

    /// 取消进行中的下载（主线程）。
    func cancel() {
        downloader?.cancel()
    }
}

/// 流式 SHA-256，避免把整个安装包读进内存。
enum FileDigest {
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1 << 20) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
