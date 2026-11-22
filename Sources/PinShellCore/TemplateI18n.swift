import Foundation

/// 模板内嵌的多语言元数据：
///
/// ```html
/// <script type="application/json" id="pinshell:i18n">
/// {
///   "default": "zh-Hans",
///   "fallback": "en",
///   "languages": {
///     "zh-Hans": { "meta": { "name": "待办事项", "description": "…" } },
///     "en": {
///       "meta": { "name": "Todo List", "description": "…" },
///       "ui": { "title": "Todo List", "clearDone": "Clear completed" }
///     }
///   }
/// }
/// </script>
/// ```
///
/// 默认语言的正文仍以内联文案为准，`ui` 可省略；非默认语言的 `ui`
/// 由 `pinshell-i18n.js` 读取。App 只解析 `meta` 做模板库展示。
public struct TemplateI18n: Equatable, Sendable {
    public struct Language: Equatable, Sendable {
        public var name: String?
        public var description: String?
    }

    public var defaultLanguage: String?
    public var fallbackLanguage: String?
    public var languages: [String: Language]

    public init(defaultLanguage: String? = nil,
                fallbackLanguage: String? = nil,
                languages: [String: Language] = [:]) {
        self.defaultLanguage = defaultLanguage
        self.fallbackLanguage = fallbackLanguage
        self.languages = languages
    }

    public var availableLanguages: [String] { Array(languages.keys) }

    // MARK: - 解析

    public static func parse(html: String) -> TemplateI18n? {
        guard let block = extractBlock(from: html),
              let root = block.json else { return nil }

        let defaultLanguage = root["default"] as? String
        let fallbackLanguage = root["fallback"] as? String
        var languages: [String: Language] = [:]

        if let rawLanguages = root["languages"] as? [String: Any] {
            for (tag, value) in rawLanguages {
                guard let entry = value as? [String: Any] else { continue }
                let meta = entry["meta"] as? [String: Any] ?? [:]
                languages[tag] = Language(
                    name: meta["name"] as? String,
                    description: meta["description"] as? String
                )
            }
        }

        guard !languages.isEmpty else { return nil }
        return TemplateI18n(defaultLanguage: defaultLanguage,
                            fallbackLanguage: fallbackLanguage,
                            languages: languages)
    }

    // MARK: - 读取 / 替换 block

    public struct Block {
        public var range: Range<String.Index>
        public var content: String
        public var json: [String: Any]?
    }

    private static let blockRegex = try? NSRegularExpression(
        pattern: #"<script\b[^>]*\bid\s*=\s*["']pinshell:i18n["'][^>]*>([\s\S]*?)</script>"#,
        options: [.caseInsensitive]
    )

    public static func extractBlock(from html: String) -> Block? {
        guard let regex = blockRegex else { return nil }
        let ns = html as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: html, range: fullRange),
              match.numberOfRanges > 1,
              let contentRange = Range(match.range(at: 1), in: html),
              let fullRange = Range(match.range, in: html) else { return nil }

        let content = String(html[contentRange])
        let json = (try? JSONSerialization.jsonObject(
            with: Data(content.utf8)
        )) as? [String: Any]
        return Block(range: fullRange, content: content, json: json)
    }

    /// 用 pretty JSON 替换 block 内容；保留 `<script …>` 标签本身。
    public static func replacingBlock(in html: String, with json: [String: Any]) -> String {
        guard let block = extractBlock(from: html),
              let content = encode(json) else { return html }

        var result = html
        // 只替换标签内容，保留属性（type/id 等）
        let openTagEnd = result.range(of: ">", range: block.range.lowerBound..<block.range.upperBound)
        let closeTagStart = result.range(of: "</script>", options: [.backwards, .caseInsensitive],
                                         range: block.range.lowerBound..<block.range.upperBound)
        guard let openTagEnd, let closeTagStart, openTagEnd.upperBound <= closeTagStart.lowerBound else {
            return html
        }
        result.replaceSubrange(openTagEnd.upperBound..<closeTagStart.lowerBound,
                               with: "\n\(content)\n")
        return result
    }

    public static func encode(_ json: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(json),
              let data = try? JSONSerialization.data(
                withJSONObject: json,
                options: [.prettyPrinted, .sortedKeys]
              ),
              var text = String(data: data, encoding: .utf8) else { return nil }
        // 避免 JSON 字符串里的 </script> 提前结束 HTML script 块。
        text = text.replacingOccurrences(of: "</script",
                                         with: "<\\/script",
                                         options: .caseInsensitive)
        return text
    }
}
