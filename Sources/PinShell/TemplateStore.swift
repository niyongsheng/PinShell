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
    /// 模板文件被写入/修改（MCP 写入、外部编辑器或目录内容变化）
    static let pinshellTemplatesChanged = Notification.Name("PinShell.templatesChanged")
}

/// 模板目录扫描器：用户目录为权威，内置模板只做缺失补齐。
enum TemplateStore {
    /// 已删除内置模板的文件名：删除后不再自动补齐，可从控制台恢复。
    private static let hiddenBuiltinsKey = "PinShell.hiddenBuiltinTemplates"

    private static let userTemplatesDir =
        ControlEndpoint.applicationDirectory().appendingPathComponent("templates", isDirectory: true)

    /// 用户模板目录 —— 手动编辑的场所，重建 App 不会覆盖
    static func userTemplatesDirectory() -> URL { userTemplatesDir }

    /// 顶层 *.html / *.htm 全量扫描；无文件时回退内置源（只读）。
    static func load() -> [TemplateItem] {
        let userDir = userTemplatesDirectory()
        seedMissingBuiltinsOnce(into: userDir)

        let items = scan(directory: userDir)
        if !items.isEmpty { return items }
        if let source = templatesDirectory {
            let hidden = hiddenBuiltinFiles()
            return scan(directory: source).filter { !hidden.contains($0.file) }
        }
        return []
    }

    /// 模板语言偏好：系统语言优先，App 支持语言兜底。
    static let preferredLanguages = LanguageTag.templatePreferredLanguages

    /// 悬浮窗加载文件时的有效元数据（与模板库显示保持一致）：
    /// 用户模板 HTML > 同名内置模板 > 默认 240×80。
    /// 非模板目录文件（示例、临时文件）只使用自身 meta，不套用模板默认尺寸。
    static func effectiveMetadata(for url: URL) -> HTMLTemplateMetadata {
        var metadata = HTMLTemplateMetadata.parse(
            fileURL: url, preferredLanguages: preferredLanguages
        )
        guard isUserTemplate(url) else { return metadata }
        if let fallback = builtinFallbacks[url.lastPathComponent] {
            metadata = metadata.fillingMissing(from: fallback)
        }
        if metadata.size == nil {
            metadata.size = WindowSize.fallback
        }
        return metadata
    }

    private static func isUserTemplate(_ url: URL) -> Bool {
        url.deletingLastPathComponent().standardizedFileURL
            == userTemplatesDirectory().standardizedFileURL
    }

    /// 内置模板元数据：每个文件只读一次，再分别按默认语言与当前语言解析。
    /// bundle 内容运行期不变，解析一次即可。
    private static let builtinMetadataMaps: (
        defaults: [String: HTMLTemplateMetadata],
        localized: [String: HTMLTemplateMetadata]
    ) = {
        guard let source = templatesDirectory else { return ([:], [:]) }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: source, includingPropertiesForKeys: nil
        )) ?? []
        var defaults: [String: HTMLTemplateMetadata] = [:]
        var localized: [String: HTMLTemplateMetadata] = [:]
        for file in files where TemplateFilePolicy.isTemplateFile(named: file.lastPathComponent) {
            guard let html = try? TemplateStorage.read(at: file) else { continue }
            let name = file.lastPathComponent
            defaults[name] = HTMLTemplateMetadata.parse(html: html)
            localized[name] = HTMLTemplateMetadata.parse(
                html: html, preferredLanguages: preferredLanguages
            )
        }
        return (defaults, localized)
    }()

    /// 内置模板的默认语言元数据（缺失补齐用）。
    private static var builtinFallbacks: [String: HTMLTemplateMetadata] {
        builtinMetadataMaps.defaults
    }

    /// 内置模板按当前语言解析后的元数据。
    /// 用户目录里的旧副本可能还没有语言变体，展示时用这里的翻译补上。
    private static var builtinLocalizedFallbacks: [String: HTMLTemplateMetadata] {
        builtinMetadataMaps.localized
    }

    /// 是否为内置模板（bundle / 仓库 Resources/templates 中的同名 HTML）。
    /// 已删除的内置模板不再算内置：同名文件可作为用户模板自由删除，
    /// 也不会被「恢复内置模板」以外的逻辑自动找回。
    static func isBuiltinTemplate(named file: String) -> Bool {
        guard !isHiddenBuiltin(named: file),
              TemplateFilePolicy.isTemplateFile(named: file),
              let source = templatesDirectory else { return false }
        return FileManager.default.fileExists(
            atPath: source.appendingPathComponent(file).path)
    }

    // MARK: - 删除 / 恢复

    static func hiddenBuiltinFiles() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: hiddenBuiltinsKey) ?? [])
    }

    static func isHiddenBuiltin(named file: String) -> Bool {
        hiddenBuiltinFiles().contains(file)
    }

    /// 删除模板文件。内置模板会记住删除状态，避免下次启动被重新补齐；
    /// 返回是否为内置模板，便于调用方展示不同提示。
    @discardableResult
    static func deleteTemplate(at url: URL) throws -> Bool {
        let file = url.lastPathComponent
        let wasBuiltin = isBuiltinTemplate(named: file)
        _ = try TemplateStorage.delete(name: file, in: url.deletingLastPathComponent())
        if wasBuiltin {
            var hidden = hiddenBuiltinFiles()
            hidden.insert(file)
            UserDefaults.standard.set(Array(hidden).sorted(), forKey: hiddenBuiltinsKey)
        }
        notifyTemplatesChanged(url)
        return wasBuiltin
    }

    /// 恢复所有被删除的内置模板（不覆盖用户已修改的同名文件）。
    static func restoreBuiltins() {
        UserDefaults.standard.removeObject(forKey: hiddenBuiltinsKey)
        seedMissingBuiltins(into: userTemplatesDirectory())
        notifyTemplatesChanged(nil)
    }

    /// 文件操作可能来自控制通道后台队列；通知统一回主线程。
    private static func notifyTemplatesChanged(_ url: URL?) {
        let post = { NotificationCenter.default.post(name: .pinshellTemplatesChanged, object: url) }
        if Thread.isMainThread {
            post()
        } else {
            DispatchQueue.main.async(execute: post)
        }
    }

    /// 模板库展示用名称/简介。
    /// 用户目录里的内置模板副本可能旧于 bundle（没有语言变体）：
    /// 只在该字段仍等于内置原文时才用 bundle 的翻译覆盖，用户改过就尊重用户。
    private static func displayMetadata(
        for file: String,
        isUser: Bool,
        metadata: HTMLTemplateMetadata,
        fallbackTitle: String
    ) -> (name: String, description: String, language: String?) {
        let defaultName = metadata.title ?? fallbackTitle
        let defaultDescription = metadata.subtitle ?? ""
        var language = metadata.resolvedLanguage
        guard isUser,
              let base = builtinFallbacks[file],
              let localized = builtinLocalizedFallbacks[file] else {
            return (defaultName, defaultDescription, language)
        }

        var name = defaultName
        var description = defaultDescription
        var overlaid = false
        if matchesBuiltin(metadata.title, base.title), let title = localized.title {
            name = title
            overlaid = true
        }
        if matchesBuiltin(metadata.subtitle, base.subtitle), let subtitle = localized.subtitle {
            description = subtitle
            overlaid = true
        }
        if overlaid {
            language = localized.resolvedLanguage ?? language
        }
        return (name, description, language)
    }

    /// 内置模板的标题可能带或不带 "PinShell · " 前缀（旧副本 / 更名）；视为同一原文。
    private static func matchesBuiltin(_ value: String?, _ base: String?) -> Bool {
        guard let value else { return true }
        guard let base else { return false }
        if value == base { return true }
        return value.replacingOccurrences(of: "PinShell · ", with: "")
            == base.replacingOccurrences(of: "PinShell · ", with: "")
    }

    /// 扫描目录并解析每个 HTML 的元数据，按 pinshell:order + title 排序。
    static func scan(directory: URL) -> [TemplateItem] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let userDir = userTemplatesDirectory().standardizedFileURL
        var items: [TemplateItem] = []
        for url in urls {
            guard TemplateFilePolicy.isTemplateFile(named: url.lastPathComponent) else { continue }
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }

            let isUser = url.deletingLastPathComponent().standardizedFileURL == userDir
            let metadata = isUser
                ? effectiveMetadata(for: url)
                : HTMLTemplateMetadata.parse(
                    fileURL: url, preferredLanguages: preferredLanguages
                )
            let fallbackTitle = url.deletingPathExtension().lastPathComponent
            let size = metadata.size ?? WindowSize.fallback
            var spec = metadata.windowSpec
            spec.size = spec.size ?? WindowSize.fallback
            let display = displayMetadata(for: url.lastPathComponent,
                                          isUser: isUser,
                                          metadata: metadata,
                                          fallbackTitle: fallbackTitle)

            items.append(TemplateItem(
                file: url.lastPathComponent,
                url: url,
                name: display.name,
                description: display.description,
                size: size,
                spec: spec,
                order: metadata.order ?? Int.max,
                language: display.language
            ))
        }

        return items.sorted { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// 首次 load 释放全部内置模板；之后不再重复检查（restoreBuiltins 可显式重建）。
    private static var hasSeededBuiltins = false
    private static let seedLock = NSLock()

    private static func seedMissingBuiltinsOnce(into dir: URL) {
        seedLock.lock()
        defer { seedLock.unlock() }
        guard !hasSeededBuiltins else { return }
        hasSeededBuiltins = true
        seedMissingBuiltins(into: dir)
    }

    /// 释放全部内置模板到用户目录；只补缺失文件，绝不覆盖用户编辑。
    private static func seedMissingBuiltins(into dir: URL) {
        let fm = FileManager.default
        guard let source = templatesDirectory, fm.fileExists(atPath: source.path) else { return }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let files = try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) else { return }
        let hidden = hiddenBuiltinFiles()
        for file in files {
            guard !hidden.contains(file.lastPathComponent) else { continue }
            let destination = dir.appendingPathComponent(file.lastPathComponent)
            if !fm.fileExists(atPath: destination.path) {
                try? fm.copyItem(at: file, to: destination)
            }
        }
    }

    /// 内置模板源：1) .app bundle 内 Contents/Resources/templates；
    /// 2) 开发布局：从可执行文件所在目录向上找仓库 Resources/templates
    ///    （兼容 .build/<arch>/release、.build/out/Products/Debug 等 SwiftPM 布局）。
    private static let templatesDirectory: URL? = {
        if let res = Bundle.main.resourceURL {
            let inBundle = res.appendingPathComponent("templates")
            if FileManager.default.fileExists(atPath: inBundle.path) { return inBundle }
        }
        var directory = Bundle.main.bundleURL
        for _ in 0..<6 {
            let candidate = directory.appendingPathComponent("Resources/templates")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            directory.deleteLastPathComponent()
        }
        return nil
    }()
}
