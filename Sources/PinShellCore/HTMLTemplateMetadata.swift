import Foundation

/// 从 HTML `<head>` 读取的模板元数据。
/// 约定：
///   <title>…</title>                         → 模板库标题
///   <meta name="description" content="…">    → 模板库副标题
///   <meta name="pinshell:title" lang="en" content="…">    → 英文标题
///   <meta name="pinshell:subtitle" lang="en" content="…"> → 英文副标题
///   <meta name="pinshell:size" content="280x64">
///   <meta name="pinshell:position" content="bottom-right">  或 "120,240"
///   <meta name="pinshell:passthrough" content="true">
///   <meta name="pinshell:opacity" content="0.85">
///   <meta name="pinshell:radius" content="18">
///   <meta name="pinshell:order" content="10">
public struct HTMLTemplateMetadata: Equatable, Sendable {
    public var title: String?
    public var subtitle: String?
    public var size: WindowSize?
    public var position: WindowPosition?
    public var passthrough: Bool?
    public var opacity: Double?
    public var radius: Double?
    public var order: Int?
    /// 模板自身的默认语言（来自 i18n block 的 `default` 或 `<html lang>`）。
    public var documentLanguage: String?
    /// i18n block 声明的全部语言；为空表示没有 block（旧模板）。
    public var availableLanguages: [String]
    /// 按当前偏好实际选中的语言（i18n block 存在时）。
    public var resolvedLanguage: String?

    public init(title: String? = nil,
                subtitle: String? = nil,
                size: WindowSize? = nil,
                position: WindowPosition? = nil,
                passthrough: Bool? = nil,
                opacity: Double? = nil,
                radius: Double? = nil,
                order: Int? = nil,
                documentLanguage: String? = nil,
                availableLanguages: [String] = [],
                resolvedLanguage: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.size = size
        self.position = position
        self.passthrough = passthrough
        self.opacity = opacity
        self.radius = radius
        self.order = order
        self.documentLanguage = documentLanguage
        self.availableLanguages = availableLanguages
        self.resolvedLanguage = resolvedLanguage
    }

    public var windowSpec: WindowSpec {
        WindowSpec(size: size, position: position, passthrough: passthrough,
                   opacity: opacity, radius: radius)
    }

    /// 只补缺失字段：用户文件自己的元数据永远优先。
    public func fillingMissing(from fallback: HTMLTemplateMetadata) -> HTMLTemplateMetadata {
        HTMLTemplateMetadata(
            title: title ?? fallback.title,
            subtitle: subtitle ?? fallback.subtitle,
            size: size ?? fallback.size,
            position: position ?? fallback.position,
            passthrough: passthrough ?? fallback.passthrough,
            opacity: opacity ?? fallback.opacity,
            radius: radius ?? fallback.radius,
            order: order ?? fallback.order,
            documentLanguage: documentLanguage ?? fallback.documentLanguage,
            // 语言能力属于文件自身，不从其他模板兜底继承；
            // 旧副本没有 block 时让页面 helper 自己按偏好选择。
            availableLanguages: availableLanguages,
            resolvedLanguage: resolvedLanguage
        )
    }

    // MARK: - 解析

    /// 读取上限与模板文件上限一致（512KB）；i18n block 可能较大。
    /// `preferredLanguages` 为空时保持旧行为（只读取默认标题/副标题）。
    public static func parse(fileURL: URL,
                             preferredLanguages: [String] = []) -> HTMLTemplateMetadata {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return HTMLTemplateMetadata()
        }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: TemplateStorage.maxBytes)) ?? Data()
        let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        return parse(html: html, preferredLanguages: preferredLanguages)
    }

    public static func parse(html: String,
                             preferredLanguages: [String] = []) -> HTMLTemplateMetadata {
        var result = HTMLTemplateMetadata()
        let fullText = String(html.prefix(TemplateStorage.maxBytes))
        let text = stripComments(fullText)

        result.documentLanguage = documentLanguage(in: text)

        // (language, rank, value)。同一语言下 rank 大的覆盖 rank 小的；
        // 语言匹配优先于未标语言的默认值。
        var titles: [(language: String?, rank: Int, value: String)] = []
        var subtitles: [(language: String?, rank: Int, value: String)] = []

        if let rawTitle = firstMatch(titleRegex, in: text, group: 1),
           let title = cleanText(rawTitle) {
            titles.append((nil, 0, title))
        }

        for tag in matches(metaTagRegex, in: text) {
            guard let name = attribute("name", in: tag)?.lowercased(),
                  let content = attribute("content", in: tag),
                  let value = cleanText(content) else { continue }
            let language = languageAttribute(in: tag)
            switch name {
            case "description":
                subtitles.append((language, 0, value))
            case "pinshell:title":
                titles.append((language, 1, value))
            case "pinshell:description":
                subtitles.append((language, 1, value))
            case "pinshell:subtitle":
                subtitles.append((language, 2, value))
            case "pinshell:size":
                result.size = WindowSize.parse(content)
            case "pinshell:position":
                result.position = WindowPosition.parse(content)
            case "pinshell:passthrough":
                result.passthrough = ValueParsing.bool(content)
            case "pinshell:opacity":
                if let value = Double(content.trimmingCharacters(in: .whitespacesAndNewlines)),
                   value.isFinite {
                    result.opacity = min(max(value, 0), 1)
                }
            case "pinshell:radius":
                if let value = Double(content.trimmingCharacters(in: .whitespacesAndNewlines)),
                   value.isFinite, value >= 0 {
                    result.radius = value
                }
            case "pinshell:order":
                if let value = Int(content.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    result.order = value
                }
            default:
                break
            }
        }

        result.title = resolve(titles,
                               preferredLanguages: preferredLanguages,
                               documentLanguage: result.documentLanguage)
        result.subtitle = resolve(subtitles,
                                  preferredLanguages: preferredLanguages,
                                  documentLanguage: result.documentLanguage)

        // i18n block 是新的单一数据源；存在时优先于旧的 lang meta。
        if let i18n = TemplateI18n.parse(html: fullText) {
            let available = i18n.availableLanguages.sorted()
            result.availableLanguages = available
            if let defaultLanguage = i18n.defaultLanguage {
                result.documentLanguage = defaultLanguage
            }
            let preferred = preferredLanguages.isEmpty
                ? [i18n.defaultLanguage].compactMap { $0 }
                : preferredLanguages
            let resolved = chooseLanguage(available: available,
                                          preferred: preferred,
                                          fallback: i18n.fallbackLanguage,
                                          defaultLanguage: i18n.defaultLanguage)
            result.resolvedLanguage = resolved

            let fallbackLanguage = i18n.fallbackLanguage
                ?? (i18n.availableLanguages.contains(where: { LanguageTag.matches($0, "en") })
                    ? "en" : i18n.defaultLanguage)
            let chosen = localizationEntry(i18n, for: resolved)
            let fallback = localizationEntry(i18n, for: fallbackLanguage)
            let base = localizationEntry(i18n, for: i18n.defaultLanguage)

            result.title = chosen?.name ?? fallback?.name ?? base?.name ?? result.title
            result.subtitle = chosen?.description ?? fallback?.description
                ?? base?.description ?? result.subtitle
        }
        return result
    }

    private static func chooseLanguage(available: [String],
                                       preferred: [String],
                                       fallback: String?,
                                       defaultLanguage: String?) -> String? {
        guard !available.isEmpty else { return nil }
        if !preferred.isEmpty,
           let match = LanguageTag.bestMatch(available: available, preferred: preferred) {
            return match
        }
        if let fallback,
           let match = LanguageTag.bestMatch(available: available, preferred: [fallback]) {
            return match
        }
        if let defaultLanguage,
           let match = LanguageTag.bestMatch(available: available, preferred: [defaultLanguage]) {
            return match
        }
        return available.first
    }

    private static func localizationEntry(_ i18n: TemplateI18n,
                                          for tag: String?) -> TemplateI18n.Language? {
        guard let tag,
              let key = LanguageTag.bestMatch(available: i18n.availableLanguages,
                                              preferred: [tag]) else { return nil }
        return i18n.languages[key]
    }

    // MARK: - 私有工具

    // 解析会在每次模板加载/刷新时执行，正则只编译一次。
    private static let commentRegex = try? NSRegularExpression(
        pattern: "<!--[\\s\\S]*?-->", options: [.caseInsensitive])
    private static let titleRegex = try? NSRegularExpression(
        pattern: #"<title\b[^>]*>([\s\S]*?)</title>"#, options: [.caseInsensitive])
    private static let metaTagRegex = try? NSRegularExpression(
        pattern: #"<meta\b[^>]*>"#, options: [.caseInsensitive])
    private static let htmlTagRegex = try? NSRegularExpression(
        pattern: #"<html\b[^>]*>"#, options: [.caseInsensitive])

    private static func documentLanguage(in html: String) -> String? {
        guard let tag = firstMatch(htmlTagRegex, in: html, group: 0) else { return nil }
        return languageAttribute(in: tag)
    }

    /// 轻量读取 `<html lang>`（不解析标题/meta/i18n），编辑器写回时使用。
    static func documentLanguage(inHTML html: String) -> String? {
        documentLanguage(in: stripComments(html))
    }

    /// 从标签中读取 `lang` / `xml:lang`；读取与写回共用同一规则。
    static func languageAttribute(in tag: String) -> String? {
        guard let raw = attribute("lang", in: tag) ?? attribute("xml:lang", in: tag) else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 按 preferredLanguages 顺序找第一个匹配的语言变体；
    /// 同一语言有多个候选时取 rank 最大的。
    /// 未标语言的内容属于模板默认语言（`<html lang>`）：
    /// 用户首选默认语言时直接用它，避免退到后面的英文变体。
    private static func resolve(
        _ entries: [(language: String?, rank: Int, value: String)],
        preferredLanguages: [String],
        documentLanguage: String?
    ) -> String? {
        guard !entries.isEmpty else { return nil }

        let untagged = entries
            .filter { $0.language == nil }
            .max(by: { $0.rank < $1.rank })

        for preferred in preferredLanguages {
            let candidates = entries.filter { entry in
                guard let language = entry.language else { return false }
                return LanguageTag.matches(language, preferred)
            }
            if let best = candidates.max(by: { $0.rank < $1.rank }) {
                return best.value
            }
            if let documentLanguage,
               LanguageTag.matches(documentLanguage, preferred),
               let untagged {
                return untagged.value
            }
        }

        return untagged?.value
    }
    private static let whitespaceRegex = try? NSRegularExpression(
        pattern: "\\s+", options: [.caseInsensitive])
    private static let attributeRegex = try? NSRegularExpression(
        pattern: #"([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))"#,
        options: [.caseInsensitive])

    private static func stripComments(_ text: String) -> String {
        guard let regex = commentRegex else { return text }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    private static func matches(_ regex: NSRegularExpression?, in text: String) -> [String] {
        guard let regex else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range) }
    }

    private static func firstMatch(_ regex: NSRegularExpression?, in text: String,
                                   group: Int) -> String? {
        guard let regex else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              group < match.numberOfRanges else { return nil }
        let range = match.range(at: group)
        guard range.location != NSNotFound else { return nil }
        return ns.substring(with: range)
    }

    /// 支持属性任意顺序、单双引号/无引号。编辑器写回时共用同一解析。
    static func attribute(_ name: String, in tag: String) -> String? {
        guard let regex = attributeRegex else { return nil }
        let ns = tag as NSString
        for match in regex.matches(in: tag, range: NSRange(location: 0, length: ns.length)) {
            guard match.numberOfRanges > 1,
                  ns.substring(with: match.range(at: 1))
                    .caseInsensitiveCompare(name) == .orderedSame else { continue }
            for index in 2..<match.numberOfRanges {
                let range = match.range(at: index)
                if range.location != NSNotFound {
                    return ns.substring(with: range)
                }
            }
        }
        return nil
    }

    private static func cleanText(_ raw: String) -> String? {
        var decoded = decodeEntities(raw)
        if let regex = whitespaceRegex {
            let range = NSRange(location: 0, length: (decoded as NSString).length)
            decoded = regex.stringByReplacingMatches(in: decoded, range: range, withTemplate: " ")
        }
        decoded = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        return decoded.isEmpty ? nil : decoded
    }

    private static func decodeEntities(_ raw: String) -> String {
        var text = raw
        let entities = [
            ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
            ("&apos;", "'"), ("&#39;", "'"), ("&nbsp;", " "),
            ("&amp;", "&"),   // &amp; 最后解码，避免二次转义
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return text
    }
}
