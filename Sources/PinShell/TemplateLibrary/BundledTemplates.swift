import Foundation
import PinShellCore

/// 内置模板播种：在线模板库不可达时，App 仍然有可用的内容。
enum BundledTemplates {
    static let fileName = "work-calendar.html"
    /// 内容版本；修改 bundled 模板时递增。老安装只补记版本，不覆盖已有模板。
    static let seedVersion = 1

    /// 目录为空且尚未播种当前版本时复制内置模板；已有模板时只记录版本。
    @discardableResult
    static func seedIfNeeded() -> URL? {
        guard AppState.bundledSeedVersion < seedVersion else { return nil }

        let directory = TemplateStore.userTemplatesDirectory()
        let existing = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        let hasTemplate = existing.contains {
            TemplateFilePolicy.isTemplateFile(named: $0.lastPathComponent)
        }
        guard !hasTemplate else {
            // 老用户升级：已有模板，跳过播种并记下版本。
            AppState.bundledSeedVersion = seedVersion
            return nil
        }

        guard let source = sourceURL else {
            NSLog("PinShell: bundled template \(fileName) is missing")
            return nil
        }

        do {
            let data = try Data(contentsOf: source)
            let url = try TemplateStorage.write(name: fileName, data: data, in: directory)
            AppState.bundledSeedVersion = seedVersion
            return url
        } catch {
            NSLog("PinShell: could not seed \(fileName): \(error.localizedDescription)")
            return nil
        }
    }

    /// App bundle 中的内置副本；开发布局下回退到仓库里的官网模板源文件。
    private static var sourceURL: URL? {
        if let url = Bundle.main.url(forResource: "work-calendar",
                                     withExtension: "html",
                                     subdirectory: "templates") {
            return url
        }

        var directory = Bundle.main.bundleURL
        for _ in 0..<6 {
            let candidate = directory
                .appendingPathComponent("website/templates/work-calendar/work-calendar.html")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            directory.deleteLastPathComponent()
        }
        return nil
    }
}
