import Foundation
import PinShellCore

/// `design-tokens.css` / `pinshell-i18n.js` 是 App 管理的共享运行时资源。
/// 启动时确保它们存在于用户模板目录；用户改过的版本会先备份再覆盖，
/// 避免旧 sidecar 让新模板悄然失效。
enum SharedTemplateAssets {
    static let names = TemplateSidecar.names

    private static let lock = NSLock()
    private static var didSeed = false

    static func seedOnce() {
        lock.lock()
        defer { lock.unlock() }
        guard !didSeed else { return }
        didSeed = true
        seed()
    }

    static func seed() {
        let fm = FileManager.default
        let destinationDirectory = ControlEndpoint.applicationDirectory()
            .appendingPathComponent("templates", isDirectory: true)
        try? fm.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        guard let sourceDirectory = sourceDirectory else { return }
        for name in names {
            let source = sourceDirectory.appendingPathComponent(name)
            guard let sourceData = try? Data(contentsOf: source) else { continue }
            let destination = destinationDirectory.appendingPathComponent(name)
            let existing = try? Data(contentsOf: destination)
            if existing == sourceData { continue }
            if fm.fileExists(atPath: destination.path) {
                backUp(destination, name: name)
            }
            do {
                try sourceData.write(to: destination, options: .atomic)
            } catch {
                NSLog("PinShell: could not seed \(name): \(error.localizedDescription)")
            }
        }
    }

    private static func backUp(_ url: URL, name: String) {
        let fm = FileManager.default
        let directory = ControlEndpoint.applicationDirectory()
            .appendingPathComponent("Backups/SharedAssets", isDirectory: true)
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = timestamp()
        let destination = directory.appendingPathComponent("\(name)-\(stamp)")
        try? fm.copyItem(at: url, to: destination)
        pruneBackups(directory: directory, prefix: "\(name)-", keeping: 5)
    }

    private static func pruneBackups(directory: URL, prefix: String, keeping: Int) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let matching = files
            .filter { $0.lastPathComponent.hasPrefix(prefix) }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                return l > r
            }
        for url in matching.dropFirst(keeping) {
            try? fm.removeItem(at: url)
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    /// bundle 优先；开发布局向上寻找仓库 Resources/templates。
    static let sourceDirectory: URL? = {
        if let resources = Bundle.main.resourceURL {
            let candidate = resources.appendingPathComponent("templates", isDirectory: true)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        var directory = Bundle.main.bundleURL
        for _ in 0..<6 {
            let candidate = directory.appendingPathComponent("Resources/templates", isDirectory: true)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            directory.deleteLastPathComponent()
        }
        return nil
    }()
}
