import AppKit

/// 把 GitHub Release 的 Markdown 说明渲染成 NSAttributedString（AppKit 属性）。
/// 覆盖 release notes 常见语法：标题、段落、列表、引用、代码、链接、表格与分隔线。
/// 不依赖 App 内其他类型，方便单独编译预览。
enum ReleaseNotesRenderer {
    private static let bodySize: CGFloat = 12.5
    private static let tableSize: CGFloat = 11.5
    private static let codeSize: CGFloat = 11.5

    static func render(_ markdown: String, width: CGFloat) -> NSAttributedString {
        do {
            // .full 才会解析标题、列表、表格等块级语法；纯内联模式会把整篇当成一段。
            let parsed = try AttributedString(markdown: markdown,
                                              options: .init(interpretedSyntax: .full),
                                              baseURL: nil)
            var builder = Builder()
            builder.ingest(parsed)
            return assemble(builder.takeBlocks(), width: width)
        } catch {
            return plainText(markdown)
        }
    }

    // MARK: - 块模型

    private enum Kind {
        case paragraph
        case heading(level: Int)
        case listItem(ordinal: Int, ordered: Bool, depth: Int)
        case quote
        case code
        case rule
        case tableRow(isHeader: Bool)
    }

    private struct Block {
        var kind: Kind
        var content: NSMutableAttributedString
    }

    private struct OpenBlock {
        var key: Int
        var kind: Kind
        var content = NSMutableAttributedString()
    }

    private struct OpenRow {
        var key: Int
        var isHeader: Bool
        var cellKey: Int
        var cells: [NSMutableAttributedString] = [NSMutableAttributedString()]
    }

    /// 遍历 AttributedString 的 run，按 presentationIntent 归并成块。
    private struct Builder {
        private var blocks: [Block] = []
        private var openBlock: OpenBlock?
        private var openRow: OpenRow?

        mutating func ingest(_ parsed: AttributedString) {
            for run in parsed.runs {
                let text = String(parsed[run.range].characters)
                let inline = run.inlinePresentationIntent
                let link = run.link

                if let cell = tableCellInfo(for: run.presentationIntent) {
                    flushBlock()
                    if var row = openRow, row.key == cell.rowKey {
                        if row.cellKey != cell.cellKey {
                            row.cellKey = cell.cellKey
                            row.cells.append(NSMutableAttributedString())
                        }
                        appendStyled(text, inline: inline, link: link,
                                     kind: .tableRow(isHeader: row.isHeader),
                                     into: row.cells[row.cells.count - 1])
                        openRow = row
                    } else {
                        flushRow()
                        let row = OpenRow(key: cell.rowKey, isHeader: cell.isHeader, cellKey: cell.cellKey)
                        appendStyled(text, inline: inline, link: link,
                                     kind: .tableRow(isHeader: cell.isHeader),
                                     into: row.cells[0])
                        openRow = row
                    }
                } else {
                    flushRow()
                    let descriptor = blockInfo(for: run.presentationIntent)
                    if openBlock?.key == descriptor.key, let block = openBlock {
                        appendStyled(text, inline: inline, link: link,
                                     kind: block.kind, into: block.content)
                    } else {
                        flushBlock()
                        let block = OpenBlock(key: descriptor.key, kind: descriptor.kind)
                        appendStyled(text, inline: inline, link: link,
                                     kind: descriptor.kind, into: block.content)
                        openBlock = block
                    }
                }
            }
            flushRow()
            flushBlock()
        }

        mutating func takeBlocks() -> [Block] {
            flushRow()
            flushBlock()
            return blocks
        }

        private mutating func flushBlock() {
            guard let block = openBlock else { return }
            blocks.append(Block(kind: block.kind, content: block.content))
            openBlock = nil
        }

        private mutating func flushRow() {
            guard let row = openRow else { return }
            let content = NSMutableAttributedString()
            for (index, cell) in row.cells.enumerated() {
                if index > 0 {
                    content.append(NSAttributedString(string: "\t", attributes: [
                        .font: NSFont.systemFont(ofSize: ReleaseNotesRenderer.tableSize),
                    ]))
                }
                content.append(cell)
            }
            blocks.append(Block(kind: .tableRow(isHeader: row.isHeader), content: content))
            openRow = nil
        }

        private func appendStyled(_ text: String,
                                  inline: InlinePresentationIntent?,
                                  link: URL?,
                                  kind: Kind,
                                  into content: NSMutableAttributedString) {
            guard !text.isEmpty else { return }
            // 硬换行（Markdown 行尾两个空格或反斜杠）
            let string = inline?.contains(.lineBreak) == true ? "\n" : text
            content.append(NSAttributedString(string: string,
                                              attributes: attributes(inline: inline, link: link, kind: kind)))
        }
    }

    // MARK: - 块属性

    private static func blockInfo(for intent: PresentationIntent?) -> (key: Int, kind: Kind) {
        guard let intent, let leaf = intent.components.first else {
            return (Int.min, .paragraph)
        }

        var level: Int?
        var isCode = false
        var isRule = false
        var isQuote = false
        var ordered = false
        var listKindFound = false
        var ordinal: Int?
        var listDepth = 0

        for component in intent.components {
            switch component.kind {
            case .header(let value):
                level = value
            case .codeBlock(_):
                isCode = true
            case .thematicBreak:
                isRule = true
            case .blockQuote:
                isQuote = true
            case .orderedList:
                // 取最近的一层列表：嵌套在有序列表里的无序列表仍是项目符号。
                if !listKindFound {
                    ordered = true
                    listKindFound = true
                }
            case .unorderedList:
                if !listKindFound {
                    ordered = false
                    listKindFound = true
                }
            case .listItem(let value):
                if ordinal == nil { ordinal = value }
                listDepth += 1
            default:
                break
            }
        }

        if let level { return (leaf.identity, .heading(level: level)) }
        if isCode { return (leaf.identity, .code) }
        if isRule { return (leaf.identity, .rule) }
        if let ordinal { return (leaf.identity, .listItem(ordinal: ordinal,
                                                          ordered: ordered,
                                                          depth: max(1, listDepth))) }
        if isQuote { return (leaf.identity, .quote) }
        return (leaf.identity, .paragraph)
    }

    private static func tableCellInfo(for intent: PresentationIntent?) -> (rowKey: Int, cellKey: Int, isHeader: Bool)? {
        guard let intent else { return nil }
        var cellKey: Int?
        var rowKey: Int?
        var isHeader = false

        for component in intent.components {
            switch component.kind {
            case .tableCell(_):
                if cellKey == nil { cellKey = component.identity }
            case .tableHeaderRow:
                if rowKey == nil { rowKey = component.identity }
                isHeader = true
            case .tableRow:
                if rowKey == nil { rowKey = component.identity }
            default:
                break
            }
        }

        guard let cellKey, let rowKey else { return nil }
        return (rowKey, cellKey, isHeader)
    }

    // MARK: - 组装

    private static func assemble(_ blocks: [Block], width: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString()

        for (index, block) in blocks.enumerated() {
            let start = result.length

            switch block.kind {
            case .listItem(let ordinal, let ordered, _):
                let prefix = ordered ? "\(ordinal).\t" : "•\t"
                result.append(NSAttributedString(string: prefix, attributes: [
                    .font: NSFont.systemFont(ofSize: bodySize),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]))
                result.append(block.content)
            case .rule:
                result.append(ruleString(width: width))
            default:
                result.append(block.content)
            }

            if !result.string.hasSuffix("\n") {
                result.append(NSAttributedString(string: "\n"))
            }
            if case .code = block.kind, index < blocks.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }

            let range = NSRange(location: start, length: result.length - start)
            result.addAttribute(.paragraphStyle,
                                value: paragraphStyle(for: block.kind, width: width, isFirst: index == 0),
                                range: range)
        }

        return result
    }

    private static func ruleString(width: CGFloat) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: 10)
        let dashWidth = ("─" as NSString).size(withAttributes: [.font: font]).width
        let count = max(8, Int((width - 20) / max(dashWidth, 1)))
        return NSAttributedString(string: String(repeating: "─", count: count), attributes: [
            .font: font,
            .foregroundColor: NSColor.tertiaryLabelColor,
        ])
    }

    private static func paragraphStyle(for kind: Kind, width: CGFloat, isFirst: Bool) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2

        switch kind {
        case .heading(let level):
            style.paragraphSpacingBefore = isFirst ? 0 : (level <= 2 ? 12 : 8)
            style.paragraphSpacing = 4
        case .listItem(_, _, let depth):
            let level = CGFloat(max(1, depth))
            style.firstLineHeadIndent = (level - 1) * 14
            style.headIndent = level * 14
            style.paragraphSpacing = 3
            style.tabStops = [NSTextTab(textAlignment: .left, location: level * 14)]
        case .quote:
            style.firstLineHeadIndent = 14
            style.headIndent = 14
            style.paragraphSpacingBefore = 4
            style.paragraphSpacing = 5
        case .code:
            style.lineSpacing = 1
            style.firstLineHeadIndent = 10
            style.headIndent = 10
            style.paragraphSpacingBefore = 4
            style.paragraphSpacing = 0
        case .rule:
            style.paragraphSpacingBefore = 8
            style.paragraphSpacing = 8
        case .tableRow(let isHeader):
            style.paragraphSpacing = isHeader ? 4 : 2
            style.tabStops = [NSTextTab(textAlignment: .left, location: max(120, width * 0.48))]
        case .paragraph:
            style.paragraphSpacing = 6
        }

        return style
    }

    // MARK: - 字符属性

    private static func attributes(inline: InlinePresentationIntent?,
                                   link: URL?,
                                   kind: Kind) -> [NSAttributedString.Key: Any] {
        var size = bodySize
        var weight: NSFont.Weight = .regular
        var mono = false
        var italic = false
        var isInlineCode = false
        var strikethrough = false
        var color: NSColor = .labelColor

        switch kind {
        case .heading(let level):
            size = level <= 1 ? 16 : (level == 2 ? 13.5 : 12.5)
            weight = level <= 2 ? .bold : .semibold
        case .code:
            mono = true
            size = codeSize
        case .quote:
            color = .secondaryLabelColor
        case .tableRow(let isHeader):
            size = tableSize
            if isHeader {
                weight = .semibold
                color = .secondaryLabelColor
            }
        case .rule:
            color = .tertiaryLabelColor
        default:
            break
        }

        if let inline {
            if inline.contains(.code) {
                mono = true
                isInlineCode = true
                size -= 0.5
            }
            if inline.contains(.stronglyEmphasized), weight == .regular {
                weight = .semibold
            }
            if inline.contains(.emphasized) {
                italic = true
            }
            if inline.contains(.strikethrough) {
                strikethrough = true
            }
        }

        var font = mono
            ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
            : NSFont.systemFont(ofSize: size, weight: weight)
        if italic {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: link == nil ? color : NSColor.linkColor,
        ]
        if strikethrough {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        if isInlineCode {
            attributes[.backgroundColor] = NSColor.labelColor.withAlphaComponent(0.07)
        }
        if let link {
            attributes[.link] = link
        }
        return attributes
    }

    // MARK: - 兜底

    private static func plainText(_ text: String) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        style.paragraphSpacing = 6
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: bodySize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: style,
        ])
    }
}
