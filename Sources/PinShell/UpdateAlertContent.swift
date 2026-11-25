import AppKit

/// 更新弹窗的内容区：可滚动的 Release 说明（渲染 Markdown）+ 底部安装提示。
@MainActor
enum UpdateAlertContent {
    private static let width: CGFloat = 440
    private static let maxNotesHeight: CGFloat = 240
    private static let hintSpacing: CGFloat = 8

    static func make(markdown: String) -> NSView {
        let rendered = ReleaseNotesRenderer.render(markdown, width: width)
        let inset = NSSize(width: 0, height: 3)

        let measured = rendered.boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let contentHeight = ceil(measured.height) + inset.height * 2
        let notesHeight = min(max(contentHeight, 32), maxNotesHeight)

        let textView = NSTextView(frame: NSRect(x: 0, y: 0,
                                                width: width,
                                                height: max(contentHeight, notesHeight)))
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = inset
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: width,
                                                       height: .greatestFiniteMagnitude)
        textView.textStorage?.setAttributedString(rendered)
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .cursor: NSCursor.pointingHand,
        ]

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: notesHeight))
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = contentHeight > notesHeight + 0.5
        scrollView.autohidesScrollers = true

        let hintText = NSLocalizedString("update.installHint", comment: "")
        let hintFont = NSFont.systemFont(ofSize: 11)
        let hintHeight = ceil((hintText as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: hintFont]
        ).height)
        let hint = NSTextField(wrappingLabelWithString: hintText)
        hint.font = hintFont
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 0, y: 0, width: width, height: hintHeight)

        let container = UpdateAlertContentView(
            frame: NSRect(x: 0, y: 0, width: width,
                          height: notesHeight + hintSpacing + hintHeight)
        )
        hint.autoresizingMask = [.width]
        scrollView.autoresizingMask = [.width, .height]
        scrollView.frame = NSRect(x: 0, y: hintHeight + hintSpacing,
                                  width: width, height: notesHeight)
        container.addSubview(hint)
        container.addSubview(scrollView)
        textView.delegate = container.linkDelegate
        return container
    }
}

/// 持有链接代理（NSTextView.delegate 是弱引用）。
private final class UpdateAlertContentView: NSView {
    let linkDelegate = ReleaseNotesLinkDelegate()
}

/// 只读文本里的链接单击后用默认浏览器打开。
@MainActor
private final class ReleaseNotesLinkDelegate: NSObject, NSTextViewDelegate {
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        let url: URL?
        if let value = link as? URL {
            url = value
        } else if let value = link as? String {
            url = URL(string: value)
        } else {
            url = nil
        }
        guard let url else { return false }
        NSWorkspace.shared.open(url)
        return true
    }
}
