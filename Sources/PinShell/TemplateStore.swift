import AppKit

/// 内置模板元数据（来自 manifest.json）
struct TemplateItem: Decodable {
    let id: String
    let name: String
    let description: String
    let file: String
    let size: Size

    struct Size: Decodable {
        let width: Double
        let height: Double
    }

    var frameSize: NSSize { NSSize(width: size.width, height: size.height) }
}

/// 模板清单：用户模板目录为权威（可手动编辑），首次启动从内置模板种子拷贝
enum TemplateStore {
    /// 用户模板目录 —— 手动编辑的场所，重建 App 不会覆盖
    static func userTemplatesDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("PinShell/templates")
    }

    static func load() -> [TemplateItem] {
        ensureUserTemplates()
        let userDir = userTemplatesDirectory()
        if let items = readManifest(in: userDir) { return items }
        // 用户目录 manifest 缺失（被误删）时回退内置源
        if let source = templatesDirectory(), let items = readManifest(in: source) {
            return items
        }
        return []
    }

    static func fileURL(for item: TemplateItem) -> URL? {
        userTemplatesDirectory().appendingPathComponent(item.file)
    }

    /// 首次启动：把内置模板（bundle / 开发目录）种子拷贝到用户目录，之后用户目录即权威
    private static func ensureUserTemplates() {
        let fm = FileManager.default
        let dir = userTemplatesDirectory()
        guard !fm.fileExists(atPath: dir.path),
              let source = templatesDirectory(),
              fm.fileExists(atPath: source.path) else { return }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for file in (try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)) ?? [] {
            try? fm.copyItem(at: file, to: dir.appendingPathComponent(file.lastPathComponent))
        }
    }

    /// 无状态，复用避免每次打开模板库都新建
    private static let decoder = JSONDecoder()

    private static func readManifest(in dir: URL) -> [TemplateItem]? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")),
              let manifest = try? decoder.decode(Manifest.self, from: data) else {
            return nil
        }
        return manifest.templates
    }

    private struct Manifest: Decodable {
        let templates: [TemplateItem]
    }

    /// 内置模板源：1) .app bundle 内 Contents/Resources/templates；
    /// 2) SPM 开发布局（裸二进制）：.build/<triple>/release → 仓库 Resources/templates
    private static func templatesDirectory() -> URL? {
        if let res = Bundle.main.resourceURL {
            let inBundle = res.appendingPathComponent("templates")
            if FileManager.default.fileExists(atPath: inBundle.path) { return inBundle }
        }
        let dev = Bundle.main.bundleURL
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/templates")
        return FileManager.default.fileExists(atPath: dev.path) ? dev : nil
    }
}
