import Foundation

/// 模板编辑器提交的字段；nil 表示不修改。
public struct HTMLTemplateEdit: Equatable, Sendable {
    public var title: String?
    public var subtitle: String?
    public var size: WindowSize?
    public var position: WindowPosition?
    public var passthrough: Bool?
    public var opacity: Double?
    public var radius: Double?
    public var order: Int?
    /// 当前编辑语言（BCP-47）。nil 或模板默认语言 → 写默认标题/副标题；
    /// 其他语言 → 写入对应 `lang` 的 meta 变体。
    public var language: String?

    public init(title: String? = nil,
                subtitle: String? = nil,
                size: WindowSize? = nil,
                position: WindowPosition? = nil,
                passthrough: Bool? = nil,
                opacity: Double? = nil,
                radius: Double? = nil,
                order: Int? = nil,
                language: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.size = size
        self.position = position
        self.passthrough = passthrough
        self.opacity = opacity
        self.radius = radius
        self.order = order
        self.language = language
    }
}

public enum HTMLTemplateEditorError: Error, LocalizedError {
    case unreadable(String)
    case unwritable(String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let path): return "Cannot read \(path)"
        case .unwritable(let message): return message
        }
    }
}

/// 把模板编辑写回 HTML：更新/插入 <title> 与 <meta name="pinshell:*">，
/// 保留文件其余内容与权限。title/subtitle 遵循已有的 pinshell 覆盖优先级。
public enum HTMLTemplateEditor {
    public static func apply(_ edit: HTMLTemplateEdit, to fileURL: URL) throws {
        guard var html = readHTML(fileURL) else {
            throw HTMLTemplateEditorError.unreadable(fileURL.path)
        }

        let requestedLanguage: String? = {
            guard let raw = edit.language?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else { return nil }
            return raw
        }()

        if let block = TemplateI18n.extractBlock(from: html), let json = block.json {
            html = applyI18nMetadata(title: edit.title,
                                     subtitle: edit.subtitle,
                                     language: requestedLanguage,
                                     json: json,
                                     in: html)
        } else {
            let documentLanguage = HTMLTemplateMetadata.documentLanguage(inHTML: html)
            let editsDefaultLanguage = requestedLanguage.map { requested in
                documentLanguage.map { LanguageTag.matches(requested, $0) } ?? true
            } ?? true
            let targetLanguage = editsDefaultLanguage
                ? (documentLanguage ?? requestedLanguage)
                : requestedLanguage

            if let title = edit.title {
                html = writeLocalizedText(title,
                                          names: ["pinshell:title"],
                                          targetLanguage: targetLanguage,
                                          isDefault: editsDefaultLanguage,
                                          fallback: .title,
                                          in: html)
            }

            if let subtitle = edit.subtitle {
                html = writeLocalizedText(subtitle,
                                          names: Self.subtitleNames,
                                          targetLanguage: targetLanguage,
                                          isDefault: editsDefaultLanguage,
                                          fallback: .meta("description", language: nil),
                                          in: html)
            }
        }

        if let size = edit.size {
            html = setMeta(named: "pinshell:size",
                           value: "\(format(size.width))x\(format(size.height))",
                           language: nil, in: html)
        }
        if let position = edit.position {
            html = setMeta(named: "pinshell:position", value: encode(position),
                           language: nil, in: html)
        }
        if let passthrough = edit.passthrough {
            html = setMeta(named: "pinshell:passthrough",
                           value: passthrough ? "true" : "false",
                           language: nil, in: html)
        }
        if let opacity = edit.opacity {
            html = setMeta(named: "pinshell:opacity",
                           value: format(min(max(opacity, 0), 1)),
                           language: nil, in: html)
        }
        if let radius = edit.radius {
            html = setMeta(named: "pinshell:radius",
                           value: format(max(radius, 0)),
                           language: nil, in: html)
        }
        if let order = edit.order {
            html = setMeta(named: "pinshell:order", value: String(order),
                           language: nil, in: html)
        }

        try write(html, to: fileURL)
    }

    /// 更新内嵌 i18n block 中目标语言的 meta；默认语言同时同步 `<title>` / description 兜底。
    private static func applyI18nMetadata(title: String?,
                                          subtitle: String?,
                                          language: String?,
                                          json: [String: Any],
                                          in html: String) -> String {
        guard title != nil || subtitle != nil else { return html }

        var root = json
        var languages = root["languages"] as? [String: Any] ?? [:]
        let available = Array(languages.keys)
        let defaultLanguage = root["default"] as? String
        let target = language ?? defaultLanguage ?? available.first ?? "en"
        let key = LanguageTag.bestMatch(available: available, preferred: [target]) ?? target

        var entry = languages[key] as? [String: Any] ?? [:]
        var meta = entry["meta"] as? [String: Any] ?? [:]
        if let title { meta["name"] = title }
        if let subtitle { meta["description"] = subtitle }
        entry["meta"] = meta
        languages[key] = entry
        root["languages"] = languages

        var result = TemplateI18n.replacingBlock(in: html, with: root)
        if let defaultLanguage,
           let defaultKey = LanguageTag.bestMatch(available: Array(languages.keys),
                                                  preferred: [defaultLanguage]),
           LanguageTag.matches(key, defaultKey) {
            if let title { result = setTitle(title, in: result) }
            if let subtitle {
                result = setMeta(named: "description", value: subtitle,
                                 language: nil, in: result)
            }
        }
        return result
    }

    /// 副标题可用的 meta 名称，优先级从高到低。
    private static let subtitleNames = ["pinshell:subtitle", "pinshell:description", "description"]

    private enum TextFallback {
        case title
        case meta(String, language: String?)
    }

    /// 写回标题/副标题：优先更新目标语言变体，默认语言再退回未标语言项，
    /// 最后才插入/更新兜底位置。标题与副标题共用同一套优先级。
    private static func writeLocalizedText(_ value: String,
                                           names: [String],
                                           targetLanguage: String?,
                                           isDefault: Bool,
                                           fallback: TextFallback,
                                           in html: String) -> String {
        if let language = targetLanguage,
           let name = firstMetaName(names, language: language, in: html) {
            return setMeta(named: name, value: value, language: language, in: html)
        }
        if isDefault {
            if let name = firstMetaName(names, language: nil, in: html) {
                return setMeta(named: name, value: value, language: nil, in: html)
            }
            switch fallback {
            case .title:
                return setTitle(value, in: html)
            case .meta(let name, let language):
                return setMeta(named: name, value: value, language: language, in: html)
            }
        }
        return setMeta(named: names[0], value: value, language: targetLanguage, in: html)
    }

    private static func firstMetaName(_ names: [String],
                                      language: String?,
                                      in html: String) -> String? {
        names.first { hasMeta(named: $0, language: language, in: html) }
    }

    // MARK: - 读取 / 写入

    private static func readHTML(_ url: URL) -> String? {
        try? TemplateStorage.read(at: url)
    }

    private static func write(_ html: String, to url: URL) throws {
        do {
            try TemplateStorage.write(html, to: url)
        } catch {
            throw HTMLTemplateEditorError.unwritable(error.localizedDescription)
        }
    }

    // MARK: - title

    private static let titleTagRegex = try? NSRegularExpression(
        pattern: #"<title\b[^>]*>[\s\S]*?</title>"#, options: [.caseInsensitive])

    private static func setTitle(_ title: String, in html: String) -> String {
        let escaped = escapeText(title)
        guard let regex = titleTagRegex else { return html }
        let ns = html as NSString
        let range = NSRange(location: 0, length: ns.length)
        if let match = regex.firstMatch(in: html, range: range),
           let stringRange = Range(match.range, in: html) {
            var result = html
            result.replaceSubrange(stringRange, with: "<title>\(escaped)</title>")
            return result
        }
        return insertIntoHead("<title>\(escaped)</title>", in: html)
    }

    // MARK: - meta

    private static func hasMeta(named name: String, language: String?,
                                in html: String) -> Bool {
        findMetaTags(named: name, language: language, in: html).isEmpty == false
    }

    private static func setMeta(named name: String, value: String, language: String?,
                                in html: String) -> String {
        let canonical: String
        if let language {
            canonical = "<meta name=\"\(escapeAttribute(name))\" content=\"\(escapeAttribute(value))\" lang=\"\(escapeAttribute(language))\">"
        } else {
            canonical = "<meta name=\"\(escapeAttribute(name))\" content=\"\(escapeAttribute(value))\">"
        }
        let matches = findMetaTags(named: name, language: language, in: html)
        if matches.isEmpty {
            return insertIntoHead(canonical, in: html)
        }

        var result = html
        for range in matches.reversed() {
            result.replaceSubrange(range, with: canonical)
        }
        return result
    }

    /// 返回 name 匹配且语言匹配的 <meta> 标签范围。
    /// `language == nil` 只匹配没有 lang 的默认项；否则匹配同语言的带 lang 变体。
    private static let metaTagRegex = try? NSRegularExpression(
        pattern: #"<meta\b[^>]*>"#, options: [.caseInsensitive])

    private static func findMetaTags(named name: String, language: String?,
                                     in html: String) -> [Range<String.Index>] {
        guard let regex = metaTagRegex else { return [] }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        var ranges: [Range<String.Index>] = []
        for match in matches {
            let tag = ns.substring(with: match.range)
            guard let actual = HTMLTemplateMetadata.attribute("name", in: tag),
                  actual.caseInsensitiveCompare(name) == .orderedSame else { continue }
            let tagLanguage = HTMLTemplateMetadata.languageAttribute(in: tag)
            if let language {
                guard let tagLanguage, LanguageTag.matches(tagLanguage, language) else { continue }
            } else {
                guard tagLanguage == nil else { continue }
            }
            if let range = Range(match.range, in: html) {
                ranges.append(range)
            }
        }
        return ranges
    }

    // MARK: - head 插入

    private static let headTagRegex = try? NSRegularExpression(
        pattern: #"<head\b[^>]*>"#, options: [.caseInsensitive])

    private static func insertIntoHead(_ snippet: String, in html: String) -> String {
        if let close = html.range(of: "</head>", options: .caseInsensitive) {
            var result = html
            result.insert(contentsOf: "\n\(snippet)\n", at: close.lowerBound)
            return result
        }
        if let regex = headTagRegex,
           let match = regex.firstMatch(in: html,
                                        range: NSRange(location: 0, length: (html as NSString).length)),
           let range = Range(match.range, in: html) {
            var result = html
            result.insert(contentsOf: "\n\(snippet)", at: range.upperBound)
            return result
        }
        if let body = html.range(of: "<body", options: .caseInsensitive) {
            var result = html
            result.insert(contentsOf: "<head>\n\(snippet)\n</head>\n", at: body.lowerBound)
            return result
        }
        return "<head>\n\(snippet)\n</head>\n" + html
    }

    // MARK: - 值编码

    private static func encode(_ position: WindowPosition) -> String {
        switch position {
        case .anchor(let anchor):
            return anchor.rawValue
        case .absolute(let x, let y):
            return "\(format(x)),\(format(y))"
        }
    }

    private static func format(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded.rounded() == rounded {
            return String(Int(rounded))
        }
        return String(format: "%.2f", rounded)
            .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
    }

    private static func escapeAttribute(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
