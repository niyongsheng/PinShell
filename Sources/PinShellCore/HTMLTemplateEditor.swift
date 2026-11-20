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

        if let title = edit.title {
            if hasMeta(named: "pinshell:title", in: html) {
                html = setMeta(named: "pinshell:title", value: title, in: html)
            } else {
                html = setTitle(title, in: html)
            }
        }

        if let subtitle = edit.subtitle {
            if hasMeta(named: "pinshell:subtitle", in: html) {
                html = setMeta(named: "pinshell:subtitle", value: subtitle, in: html)
            } else if hasMeta(named: "pinshell:description", in: html) {
                html = setMeta(named: "pinshell:description", value: subtitle, in: html)
            } else {
                html = setMeta(named: "description", value: subtitle, in: html)
            }
        }

        if let size = edit.size {
            html = setMeta(named: "pinshell:size",
                           value: "\(format(size.width))x\(format(size.height))",
                           in: html)
        }
        if let position = edit.position {
            html = setMeta(named: "pinshell:position", value: encode(position), in: html)
        }
        if let passthrough = edit.passthrough {
            html = setMeta(named: "pinshell:passthrough",
                           value: passthrough ? "true" : "false",
                           in: html)
        }
        if let opacity = edit.opacity {
            html = setMeta(named: "pinshell:opacity",
                           value: format(min(max(opacity, 0), 1)),
                           in: html)
        }
        if let radius = edit.radius {
            html = setMeta(named: "pinshell:radius",
                           value: format(max(radius, 0)),
                           in: html)
        }
        if let order = edit.order {
            html = setMeta(named: "pinshell:order", value: String(order), in: html)
        }

        try write(html, to: fileURL)
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

    private static func setTitle(_ title: String, in html: String) -> String {
        let escaped = escapeText(title)
        let pattern = #"<title\b[^>]*>[\s\S]*?</title>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return html
        }
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

    private static func hasMeta(named name: String, in html: String) -> Bool {
        findMetaTags(named: name, in: html).isEmpty == false
    }

    private static func setMeta(named name: String, value: String, in html: String) -> String {
        let canonical = "<meta name=\"\(escapeAttribute(name))\" content=\"\(escapeAttribute(value))\">"
        let matches = findMetaTags(named: name, in: html)
        if matches.isEmpty {
            return insertIntoHead(canonical, in: html)
        }

        var result = html
        for range in matches.reversed() {
            result.replaceSubrange(range, with: canonical)
        }
        return result
    }

    /// 返回所有 name 匹配的 <meta> 标签范围（HTML 属性顺序无关）。
    private static func findMetaTags(named name: String, in html: String) -> [Range<String.Index>] {
        let tagPattern = #"<meta\b[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: tagPattern, options: [.caseInsensitive]) else {
            return []
        }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        var ranges: [Range<String.Index>] = []
        for match in matches {
            let tag = ns.substring(with: match.range)
            guard let actual = HTMLTemplateMetadata.attribute("name", in: tag),
                  actual.caseInsensitiveCompare(name) == .orderedSame else { continue }
            if let range = Range(match.range, in: html) {
                ranges.append(range)
            }
        }
        return ranges
    }

    // MARK: - head 插入

    private static func insertIntoHead(_ snippet: String, in html: String) -> String {
        if let close = html.range(of: "</head>", options: .caseInsensitive) {
            var result = html
            result.insert(contentsOf: "\n\(snippet)\n", at: close.lowerBound)
            return result
        }
        let headPattern = #"<head\b[^>]*>"#
        if let regex = try? NSRegularExpression(pattern: headPattern, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: (html as NSString).length)),
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
