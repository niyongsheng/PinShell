import AppKit
import PinShellCore

/// 模板元数据完全来自 HTML 自身：
/// <title> → 卡片标题，<meta name="description"> → 副标题，
/// <meta name="pinshell:*"> → 窗口属性 / 排序。
struct TemplateItem: Equatable {
    let file: String
    let url: URL
    let name: String
    let description: String
    let size: WindowSize
    let spec: WindowSpec
    let order: Int
    /// 当前展示/编辑的语言（i18n block 选中项）。
    let language: String?

    var frameSize: NSSize { NSSize(width: size.width, height: size.height) }
}

extension Notification.Name {
    /// 模板文件被写入/修改（MCP 写入、模板库安装、外部编辑器或目录内容变化）
    static let pinshellTemplatesChanged = Notification.Name("PinShell.templatesChanged")
}

/// 用户模板目录扫描器。模板由在线模板库安装，App 不再内置 HTML；
/// 只负责把共享 sidecars 播种进目录。
enum TemplateStore {
    private static let userTemplatesDir =
        ControlEndpoint.applicationDirectory().appendingPathComponent("templates", isDirectory: true)

    /// 用户模板目录 —— 手动编辑的场所，重建 App 不会覆盖
    static func userTemplatesDirectory() -> URL { userTemplatesDir }

    /// 顶层 *.html / *.htm 扫描。
    static func load() -> [TemplateItem] {
        let directory = userTemplatesDirectory()
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        SharedTemplateAssets.seedOnce()
        return scan(directory: directory)
    }

    /// 模板语言偏好：系统语言优先，App 支持语言兜底。
    static let preferredLanguages = LanguageTag.templatePreferredLanguages

    private struct CachedMetadata {
        let modified: Date?
        let fileSize: Int?
        let metadata: HTMLTemplateMetadata
    }

    private static let metadataLock = NSLock()
    private static var metadataCache: [URL: CachedMetadata] = [:]

    /// 解析模板元数据；文件未变化（mtime + size）时复用上次结果。
    static func cachedMetadata(for url: URL) -> HTMLTemplateMetadata {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modified = values?.contentModificationDate
        let fileSize = values?.fileSize

        metadataLock.lock()
        if let cached = metadataCache[url],
           cached.modified == modified, cached.fileSize == fileSize {
            metadataLock.unlock()
            return cached.metadata
        }
        metadataLock.unlock()

        let metadata = HTMLTemplateMetadata.parse(
            fileURL: url, preferredLanguages: preferredLanguages
        )

        metadataLock.lock()
        if metadataCache.count >= 64 { metadataCache.removeAll() }
        metadataCache[url] = CachedMetadata(modified: modified, fileSize: fileSize, metadata: metadata)
        metadataLock.unlock()
        return metadata
    }

    /// 每个模板的窗口元数据；用户模板目录里的文件缺尺寸时用 240×80 兜底。
    static func effectiveMetadata(for url: URL) -> HTMLTemplateMetadata {
        var metadata = cachedMetadata(for: url)
        guard isUserTemplate(url) else { return metadata }
        if metadata.size == nil {
            metadata.size = WindowSize.fallback
        }
        return metadata
    }

    private static func isUserTemplate(_ url: URL) -> Bool {
        url.deletingLastPathComponent().standardizedFileURL
            == userTemplatesDirectory().standardizedFileURL
    }

    @discardableResult
    static func deleteTemplate(at url: URL) throws -> Bool {
        _ = try TemplateStorage.delete(name: url.lastPathComponent,
                                       in: url.deletingLastPathComponent())
        notifyTemplatesChanged(url)
        return false
    }

    /// 文件操作可能来自控制通道后台队列；通知统一回主线程。
    static func notifyTemplatesChanged(_ url: URL?) {
        if let url {
            metadataLock.lock()
            metadataCache.removeValue(forKey: url)
            metadataLock.unlock()
        }
        let post = { NotificationCenter.default.post(name: .pinshellTemplatesChanged, object: url) }
        if Thread.isMainThread {
            post()
        } else {
            DispatchQueue.main.async(execute: post)
        }
    }

    /// 扫描目录并解析每个 HTML 的元数据，按 pinshell:order + title 排序。
    static func scan(directory: URL) -> [TemplateItem] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var items: [TemplateItem] = []
        for url in urls {
            guard TemplateFilePolicy.isTemplateFile(named: url.lastPathComponent) else { continue }
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                continue
            }

            let metadata = effectiveMetadata(for: url)
            let fallbackTitle = url.deletingPathExtension().lastPathComponent
            let size = metadata.size ?? WindowSize.fallback
            var spec = metadata.windowSpec
            spec.size = spec.size ?? WindowSize.fallback

            items.append(TemplateItem(
                file: url.lastPathComponent,
                url: url,
                name: metadata.title ?? fallbackTitle,
                description: metadata.subtitle ?? "",
                size: size,
                spec: spec,
                order: metadata.order ?? Int.max,
                language: metadata.resolvedLanguage
            ))
        }

        return items.sorted { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
