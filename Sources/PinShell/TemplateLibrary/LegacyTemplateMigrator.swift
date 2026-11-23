import Foundation
import PinShellCore

/// 1.5 首次启动：把 1.4 播种且未被修改的模板登记为 1.0.0。
/// 只登记，不写模板文件；改过或更旧的副本保持“本地未托管”。
enum LegacyTemplateMigrator {
    static func migrate(state: TemplateLibraryState,
                        templatesDirectory: URL,
                        sourceCatalog: URL) -> TemplateLibraryState {
        UserDefaults.standard.removeObject(forKey: "PinShell.hiddenBuiltinTemplates")
        guard let index = loadIndex() else { return state }

        var state = state
        let fm = FileManager.default
        for legacy in index.templates {
            guard state.installed[legacy.id] == nil else { continue }
            let url = templatesDirectory.appendingPathComponent(legacy.file)
            guard fm.fileExists(atPath: url.path),
                  let hash = try? FileDigest.sha256(of: url),
                  hash == legacy.sha256 else { continue }
            state.installed[legacy.id] = InstalledTemplateRecord(
                version: legacy.version,
                sha256: hash,
                installedAt: Date(),
                sourceCatalog: sourceCatalog.absoluteString
            )
        }
        return state
    }

    static func loadIndex() -> LegacyTemplateIndex? {
        let fm = FileManager.default
        if let url = Bundle.main.url(forResource: "legacy-templates",
                                     withExtension: "json"),
           let data = try? Data(contentsOf: url) {
            return try? JSONDecoder().decode(LegacyTemplateIndex.self, from: data)
        }

        var directory = Bundle.main.bundleURL
        for _ in 0..<6 {
            let candidate = directory.appendingPathComponent("Resources/legacy-templates.json")
            if fm.fileExists(atPath: candidate.path),
               let data = try? Data(contentsOf: candidate) {
                return try? JSONDecoder().decode(LegacyTemplateIndex.self, from: data)
            }
            directory.deleteLastPathComponent()
        }
        return nil
    }
}
