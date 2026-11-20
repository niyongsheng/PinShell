import Foundation

/// 监视当前 HTML：轮询 size + mtime 签名。
/// 对 agent / 编辑器都可靠：直接写入、truncate+write、原子 rename 都能检测到；
/// 签名连续两次一致（0.2s 稳定窗口）才回调，避免读到半截文件。
final class FileWatcher {
    private struct FileSignature: Equatable {
        let size: Int64
        let modified: TimeInterval
    }

    private let watcher: PollingWatcher<FileSignature?>

    init(url: URL, onChange: @escaping () -> Void) {
        watcher = PollingWatcher(
            label: "PinShell.FileWatcher",
            pollInterval: 0.25,
            settleDelay: 0.2,
            signature: { Self.signature(of: url) },
            onChange: onChange
        )
    }

    func start() { watcher.start() }
    func stop() { watcher.stop() }

    private static func signature(of url: URL) -> FileSignature? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber,
              let modified = attrs[.modificationDate] as? Date else { return nil }
        return FileSignature(size: size.int64Value,
                             modified: modified.timeIntervalSince1970)
    }
}
