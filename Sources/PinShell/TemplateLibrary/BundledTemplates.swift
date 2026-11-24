import Foundation
import PinShellCore

/// 首次安装时播种的内置模板：在线模板库不可达时，App 仍然有可用的内容。
enum BundledTemplates {
    static let fileName = "work-calendar.html"

    /// 用户模板目录为空时，把内置工作日历复制进去并返回其 URL。
    /// 已有任何 HTML 模板时不覆盖、不追加。
    @discardableResult
    static func seedIfNeeded() -> URL? {
        let directory = TemplateStore.userTemplatesDirectory()
        let existing = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        let hasTemplate = existing.contains {
            TemplateFilePolicy.isTemplateFile(named: $0.lastPathComponent)
        }
        guard !hasTemplate else { return nil }

        guard let source = sourceURL else {
            NSLog("PinShell: bundled template \(fileName) is missing")
            return nil
        }

        do {
            let data = try Data(contentsOf: source)
            return try TemplateStorage.write(name: fileName, data: data, in: directory)
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
