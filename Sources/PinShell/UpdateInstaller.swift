import AppKit
import PinShellCore

/// 半自动更新：下载 Release 中的 pkg → 可选 SHA-256 校验 → 交给系统 Installer。
/// 应用没有 Developer ID 签名，因此不做原地替换；安装与管理员授权由 Installer 完成。
/// 安装完成后自动退出并重新启动到新版本。
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

    /// 等待安装完成的最长时间（用户可能很晚才输入管理员密码）。
    private static let installTimeout: TimeInterval = 30 * 60

    private var progressWindow: UpdateProgressWindowController?
    private var downloader: UpdateDownloader?
    private(set) var isInstalling = false

    /// 下载并打开安装器，等待安装完成后自动重启。用户取消时抛出 CancellationError。
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
        let installStartedAt = Date()
        // 先注册通知再打开 pkg，避免 Installer 启动早于观察者导致漏掉首条事件。
        let activity = InstallerActivity()
        guard NSWorkspace.shared.open(file) else {
            activity.invalidate()
            throw InstallError.openInstallerFailed
        }

        window.setPhase(NSLocalizedString("update.waitingForInstall", comment: ""))
        try await waitForInstall(release: release, startedAt: installStartedAt, activity: activity)

        window.setPhase(NSLocalizedString("update.restarting", comment: ""))
        try? await Task.sleep(nanoseconds: 800_000_000)
        relaunchInstalledApp()
    }

    /// 取消进行中的下载（主线程）。
    func cancel() {
        downloader?.cancel()
    }

    // MARK: - 等待安装

    /// 用 Installer 的启动/退出通知唤醒检查，避免高频枚举进程。
    /// 回执可读时以 InstallDate 为准；没有回执（例如 make install）时比较磁盘版本。
    /// 用户在 Installer 中取消或关闭窗口时抛出 CancellationError。
    private func waitForInstall(release: UpdateChecker.ReleaseInfo,
                                startedAt: Date,
                                activity: InstallerActivity) async throws {
        let deadline = startedAt.addingTimeInterval(Self.installTimeout)
        let targetVersion = release.versionLabel
        defer { activity.invalidate() }
        var lastVersion: String?

        while Date() < deadline {
            try Task.checkCancellation()

            if let receipt = Self.readInstallReceipt() {
                // 回执可读时只认 InstallDate：安装失败留下新 Info.plist 也不会被误判为成功。
                if Self.receiptShowsFinished(receipt, startedAt: startedAt, targetVersion: targetVersion) {
                    return
                }
            } else {
                // 没有回执时按版本判断：连续两次读到目标版本（避开解包中途），
                // 或安装器已退出，都视为完成。
                let version = Self.installedVersion()
                if version == targetVersion,
                   lastVersion == version || (activity.seen && !activity.running) {
                    return
                }
                lastVersion = version
            }

            // 安装器已关闭但安装没有完成：用户取消或安装失败
            if activity.seen && !activity.running {
                throw CancellationError()
            }
            // 安装器始终没出现（例如被系统拦截），不再等待
            if !activity.seen && Date().timeIntervalSince(startedAt) > 90 {
                throw CancellationError()
            }

            await activity.waitForChange(timeout: 2)
        }
        throw CancellationError()
    }

    /// 解析 pkg 回执；文件不存在/不可读/缺少 InstallDate 时返回 nil。
    private static func readInstallReceipt() -> (installDate: Date, version: String?)? {
        guard let data = try? Data(contentsOf: PinShellAppInfo.receiptURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let installDate = plist["InstallDate"] as? Date
        else { return nil }
        return (installDate, plist["PackageVersion"] as? String)
    }

    private static func receiptShowsFinished(_ receipt: (installDate: Date, version: String?),
                                             startedAt: Date,
                                             targetVersion: String) -> Bool {
        guard receipt.installDate >= startedAt.addingTimeInterval(-1) else { return false }
        if let version = receipt.version {
            return VersionNumber.compare(version, targetVersion) == .orderedSame
        }
        return true
    }

    private static func installedVersion() -> String? {
        let plistURL = PinShellAppInfo.installedAppURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return plist["CFBundleShortVersionString"] as? String
    }

    // MARK: - 重启

    /// 新版本已就位：启动一个独立 shell，等旧进程退出后打开新版本，然后退出当前进程。
    /// 必须用独立进程——本进程退出后就没有机会再执行代码了。
    private func relaunchInstalledApp() {
        let path = PinShellAppInfo.installedAppURL.path
        let quotedPath = "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        // 按完整命令行精确匹配主进程（"PinShell mcp" 子进程不应算在内）。
        let runningExecutable = Bundle.main.executableURL?.path
            ?? PinShellAppInfo.installedExecutableURL.path
        let quotedExecutable = "'" + runningExecutable.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let script = """
        n=0
        while [ $n -lt 40 ] && /usr/bin/pgrep -f -x -U $(/usr/bin/id -u) \(quotedExecutable) >/dev/null 2>&1; do
            /bin/sleep 0.25
            n=$((n+1))
        done
        /usr/bin/open -a \(quotedPath)
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        do {
            try process.run()
        } catch {
            // 无法拉起重启进程时保留当前实例，提示用户手动重启。
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("update.installedTitle", comment: "")
            alert.informativeText = NSLocalizedString("update.relaunchFailed", comment: "")
            alert.addButton(withTitle: NSLocalizedString("console.error.ok", comment: ""))
            alert.runAppModal()
            return
        }
        NSApp.terminate(nil)
    }
}

/// 跟踪 Installer 的启动/退出；只在主线程使用。
private final class InstallerActivity: @unchecked Sendable {
    private(set) var seen: Bool
    private(set) var running: Bool
    private var observers: [NSObjectProtocol] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init() {
        running = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == PinShellAppInfo.installerBundleIdentifier
        }
        seen = running

        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard Self.isInstaller(note) else { return }
            self?.seen = true
            self?.running = true
            self?.resumeWaiters()
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard Self.isInstaller(note) else { return }
            self?.running = false
            self?.resumeWaiters()
        })
    }

    deinit {
        invalidate()
    }

    func invalidate() {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
        observers.removeAll()
        resumeWaiters()
    }

    /// 等待下一次 Installer 启动/退出；超时后返回，由调用方重新检查状态。
    func waitForChange(timeout: TimeInterval) async {
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.resumeWaiters()
            }
        }
    }

    private func resumeWaiters() {
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }

    private static func isInstaller(_ note: Notification) -> Bool {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        else { return false }
        return app.bundleIdentifier == PinShellAppInfo.installerBundleIdentifier
    }
}
