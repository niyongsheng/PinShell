import Foundation

/// 从 HTML `<head>` 读取的模板元数据。
/// 约定：
///   <title>…</title>                         → 模板库标题
///   <meta name="description" content="…">    → 模板库副标题
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

    public init(title: String? = nil,
                subtitle: String? = nil,
                size: WindowSize? = nil,
                position: WindowPosition? = nil,
                passthrough: Bool? = nil,
                opacity: Double? = nil,
                radius: Double? = nil,
                order: Int? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.size = size
        self.position = position
        self.passthrough = passthrough
        self.opacity = opacity
        self.radius = radius
        self.order = order
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
            order: order ?? fallback.order
        )
    }

    // MARK: - 解析

    /// 最多读取 64KB，足以覆盖所有模板的 <head>。
    public static func parse(fileURL: URL) -> HTMLTemplateMetadata {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return HTMLTemplateMetadata()
        }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 64 * 1024)) ?? Data()
        let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        return parse(html: html)
    }

    public static func parse(html: String) -> HTMLTemplateMetadata {
        var result = HTMLTemplateMetadata()
        var text = String(html.prefix(64 * 1024))
        text = stripComments(text)

        if let rawTitle = firstMatch(titleRegex, in: text, group: 1) {
            result.title = cleanText(rawTitle)
        }

        // 标准 description 与 pinshell 专用覆盖分开收集，保证覆盖与文档顺序无关
        var descriptionValue: String?
        var subtitleOverride: String?

        for tag in matches(metaTagRegex, in: text) {
            guard let name = attribute("name", in: tag)?.lowercased(),
                  let content = attribute("content", in: tag) else { continue }
            switch name {
            case "description":
                descriptionValue = cleanText(content)
            case "pinshell:title":
                result.title = cleanText(content)
            case "pinshell:subtitle", "pinshell:description":
                subtitleOverride = cleanText(content)
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
        result.subtitle = subtitleOverride ?? descriptionValue
        return result
    }

    // MARK: - 私有工具

    // 解析会在每次模板加载/刷新时执行，正则只编译一次。
    private static let commentRegex = try? NSRegularExpression(
        pattern: "<!--[\\s\\S]*?-->", options: [.caseInsensitive])
    private static let titleRegex = try? NSRegularExpression(
        pattern: #"<title\b[^>]*>([\s\S]*?)</title>"#, options: [.caseInsensitive])
    private static let metaTagRegex = try? NSRegularExpression(
        pattern: #"<meta\b[^>]*>"#, options: [.caseInsensitive])
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
