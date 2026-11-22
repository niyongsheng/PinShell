import Foundation
import PinShellCore

/// 监视模板目录：轮询文件名 + 大小 + 修改时间签名。
/// agent 通过 MCP、编辑器或文件工具改动模板时都能检测到；
/// 签名稳定 0.3s 后才回调，避免半截写入。
final class TemplateDirectoryWatcher {
    private let watcher: PollingWatcher<String>

    init(directory: URL, onChange: @escaping () -> Void) {
        watcher = PollingWatcher(
            label: "PinShell.TemplateDirectoryWatcher",
            pollInterval: 0.6,
            settleDelay: 0.3,
            leeway: .milliseconds(150),
            signature: { Self.signature(of: directory) },
            onChange: onChange
        )
    }

    func start() { watcher.start() }
    func stop() { watcher.stop() }

    private static func signature(of directory: URL) -> String {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]) else {
            return ""
        }
        return entries
            .filter { TemplateFilePolicy.isTemplateFile(named: $0.lastPathComponent) }
            .map { url -> String in
                let values = try? url.resourceValues(forKeys: Set(keys))
                let size = values?.fileSize ?? 0
                let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
                return "\(url.lastPathComponent)|\(size)|\(modified)"
            }
            .sorted()
            .joined(separator: "\n")
    }
}
