import AppKit
import WebKit
import PinShellCore

/// 控制台右侧详情：模板预览/应用/编辑，或 MCP 服务说明。
final class ConsoleDetailViewController: NSViewController {
    var onApply: ((TemplateItem) -> Void)?
    var onDelete: ((TemplateItem) -> Void)?

    private(set) var currentTemplate: TemplateItem?

    private let fileLabel = NSTextField(labelWithString: "—")
    private let frameChip = StatusChip()
    private let visibleChip = StatusChip()
    private let passthroughChip = StatusChip()
    private let watchChip = StatusChip()

    private let contentContainer = NSView()
    private let templatePage = NSView()
    private let emptyPage = NSView()
    /// MCP 页在首次打开时才构建，避免打开控制台就创建整套卡片。
    private var mcpView: ConsoleMCPView?
    private let aboutView = ConsoleAboutView()

    private let previewWebView = WKWebView(frame: .zero)
    private let previewCard = GlassCard(cornerRadius: 22)
    private var previewHeightConstraint: NSLayoutConstraint?
    private let titleLabel = NSTextField(labelWithString: "—")
    private let subtitleLabel = NSTextField(wrappingLabelWithString: "")
    private let sizeChip = StatusChip()
    private let positionChip = StatusChip()
    private let orderChip = StatusChip()
    private let applyButton = NSButton(title: NSLocalizedString("console.apply", comment: ""),
                                       target: nil, action: nil)
    private let deleteButton = NSButton(title: NSLocalizedString("console.detail.delete", comment: ""),
                                        target: nil, action: nil)

    private static let enableBlue = NSColor(srgbRed: 0.16, green: 0.43, blue: 0.85, alpha: 1)
    private static let deleteRed = NSColor(srgbRed: 0.85, green: 0.23, blue: 0.22, alpha: 1)

    /// SF Symbol 默认跟随系统着色；彩色按钮上需要显式的白色版本。
    private static func whiteSymbol(_ name: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
    }

    override func loadView() {
        let root = NSVisualEffectView()
        root.material = .underWindowBackground
        root.blendingMode = .behindWindow
        root.state = .active
        view = root
        build()
    }

    // MARK: - 装配

    private func build() {
        let statusBar = buildStatusBar()

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusBar)
        view.addSubview(contentContainer)

        statusBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            statusBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22),
            statusBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -22),

            contentContainer.topAnchor.constraint(equalTo: statusBar.bottomAnchor, constant: 12),
            contentContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
        ])

        buildTemplatePage()
        buildEmptyPage()
        for page in [templatePage, emptyPage, aboutView] {
            page.translatesAutoresizingMaskIntoConstraints = false
            contentContainer.addSubview(page)
            NSLayoutConstraint.activate([
                page.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
                page.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
                page.topAnchor.constraint(equalTo: contentContainer.topAnchor),
                page.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
            ])
        }
        emptyPage.isHidden = true
        aboutView.isHidden = true
    }

    private func buildStatusBar() -> NSView {
        let icon = NSImageView(image: NSImage(systemSymbolName: "macwindow",
                                              accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.heightAnchor.constraint(equalToConstant: 14),
        ])

        fileLabel.font = .systemFont(ofSize: 12, weight: .medium)
        fileLabel.textColor = .labelColor
        fileLabel.lineBreakMode = .byTruncatingMiddle
        fileLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let left = NSStackView(views: [icon, fileLabel])
        left.orientation = .horizontal
        left.spacing = 6
        left.alignment = .centerY

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let right = NSStackView(views: [frameChip, visibleChip, passthroughChip, watchChip])
        right.orientation = .horizontal
        right.spacing = 6
        right.alignment = .centerY
        right.setContentHuggingPriority(.required, for: .horizontal)

        let bar = NSStackView(views: [left, spacer, right])
        bar.orientation = .horizontal
        bar.spacing = 8
        bar.alignment = .centerY
        return bar
    }

    private func buildTemplatePage() {
        previewWebView.makeTransparent()
        previewWebView.autoresizingMask = []
        previewCard.contentView.addSubview(previewWebView)
        previewCard.translatesAutoresizingMaskIntoConstraints = false

        // 高度跟随模板声明高度，空间不足时（优先级 750）可被压缩，
        // 保证下方标题与操作按钮始终可见
        let height = previewCard.heightAnchor.constraint(equalToConstant: 236)
        height.priority = .defaultHigh
        height.isActive = true
        previewHeightConstraint = height

        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        subtitleLabel.font = .systemFont(ofSize: 12.5)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.maximumNumberOfLines = 2
        subtitleLabel.lineBreakMode = .byWordWrapping

        let metaRow = NSStackView(views: [sizeChip, positionChip, orderChip, NSView()])
        metaRow.orientation = .horizontal
        metaRow.spacing = 6
        metaRow.alignment = .centerY
        metaRow.distribution = .fill

        applyButton.target = self
        applyButton.action = #selector(applyTapped)
        applyButton.bezelStyle = .rounded
        applyButton.controlSize = .large
        applyButton.font = .systemFont(ofSize: 12.5, weight: .semibold)
        applyButton.bezelColor = Self.enableBlue
        applyButton.contentTintColor = .white
        applyButton.image = Self.whiteSymbol("pin.fill")
        applyButton.imagePosition = .imageLeading
        applyButton.attributedTitle = NSAttributedString(
            string: applyButton.title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12.5, weight: .semibold),
                .foregroundColor: NSColor.white,
            ]
        )
        applyButton.keyEquivalent = "\r"

        deleteButton.target = self
        deleteButton.action = #selector(deleteTapped)
        deleteButton.bezelStyle = .rounded
        deleteButton.controlSize = .large
        deleteButton.font = .systemFont(ofSize: 12.5)
        deleteButton.bezelColor = Self.deleteRed
        deleteButton.contentTintColor = .white
        deleteButton.image = Self.whiteSymbol("trash")
        deleteButton.imagePosition = .imageLeading
        deleteButton.attributedTitle = NSAttributedString(
            string: deleteButton.title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12.5, weight: .medium),
                .foregroundColor: NSColor.white,
            ]
        )

        let actions = NSStackView(views: [applyButton, deleteButton, NSView()])
        actions.orientation = .horizontal
        actions.spacing = 8
        actions.alignment = .centerY

        let stack = NSStackView(views: [previewCard, titleLabel, subtitleLabel, metaRow, actions])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        templatePage.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: templatePage.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: templatePage.trailingAnchor, constant: -22),
            stack.topAnchor.constraint(equalTo: templatePage.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: templatePage.bottomAnchor, constant: -8),
            previewCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
            titleLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            subtitleLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            metaRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            actions.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private func buildEmptyPage() {
        let icon = NSImageView(image: NSImage(systemSymbolName: "rectangle.on.rectangle.slash",
                                              accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .tertiaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 38),
            icon.heightAnchor.constraint(equalToConstant: 38),
        ])

        let title = NSTextField(labelWithString: NSLocalizedString("console.empty.title", comment: ""))
        title.font = .systemFont(ofSize: 15, weight: .semibold)

        let subtitle = NSTextField(wrappingLabelWithString:
            NSLocalizedString("console.empty.subtitle", comment: ""))
        subtitle.font = .systemFont(ofSize: 11.5)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center
        subtitle.widthAnchor.constraint(lessThanOrEqualToConstant: 340).isActive = true

        let openFolder = NSButton(title: NSLocalizedString("console.empty.openFolder", comment: ""),
                                  target: self, action: #selector(openTemplatesFolder))
        openFolder.bezelStyle = .rounded
        openFolder.controlSize = .large
        openFolder.font = .systemFont(ofSize: 12.5, weight: .medium)
        openFolder.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        openFolder.imagePosition = .imageLeading

        let stack = NSStackView(views: [icon, title, subtitle, openFolder])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        emptyPage.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: emptyPage.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: emptyPage.centerYAnchor, constant: -20),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: emptyPage.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: emptyPage.trailingAnchor, constant: -32),
        ])
    }

    // MARK: - 页面切换

    private enum Page {
        case template, empty, mcp, about
    }

    private func show(_ page: Page) {
        if page == .mcp { ensureMCPView() }
        templatePage.isHidden = page != .template
        emptyPage.isHidden = page != .empty
        mcpView?.isHidden = page != .mcp
        aboutView.isHidden = page != .about
    }

    private func ensureMCPView() {
        guard mcpView == nil else { return }
        let view = ConsoleMCPView()
        view.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
        view.isHidden = true
        mcpView = view
    }

    func showTemplate(_ item: TemplateItem) {
        currentTemplate = item
        show(.template)

        titleLabel.stringValue = item.name
        subtitleLabel.stringValue = item.description
        sizeChip.update(text: "\(NumberFormat.text(item.size.width))×\(NumberFormat.text(item.size.height))",
                        active: true, activeColor: .controlAccentColor, symbol: "aspectratio")
        positionChip.update(text: positionText(item.spec.position),
                            active: true, activeColor: .controlAccentColor,
                            symbol: "rectangle.inset.filled")
        if item.order == Int.max {
            orderChip.isHidden = true
        } else {
            orderChip.isHidden = false
            orderChip.update(text: "#\(item.order)", active: true,
                             activeColor: .controlAccentColor, symbol: "number")
        }

        // 卡片上下各有 16pt 内边距：让 HTML 以其声明高度 1:1 展示
        previewHeightConstraint?.constant = max(96, item.size.height + 32)
        previewWebView.layer?.setAffineTransform(.identity)
        previewWebView.loadLocalHTMLFile(item.url)
        view.layoutSubtreeIfNeeded()
        layoutPreview()
    }

    func showEmpty() {
        currentTemplate = nil
        show(.empty)
    }

    func showMCP() {
        currentTemplate = nil
        show(.mcp)
        mcpView?.refresh()
    }

    func showAbout() {
        currentTemplate = nil
        show(.about)
    }

    func refreshStatus(_ status: JSONValue) {
        let path = status["file"]?.stringValue
        fileLabel.stringValue = path.map { ($0 as NSString).lastPathComponent }
            ?? NSLocalizedString("console.noFile", comment: "")
        fileLabel.toolTip = path

        if let frame = status["frame"],
           let width = frame["width"]?.doubleValue,
           let height = frame["height"]?.doubleValue {
            frameChip.isHidden = false
            frameChip.update(text: "\(NSLocalizedString("console.chip.frame", comment: "")) "
                                  + "\(NumberFormat.text(width))×\(NumberFormat.text(height))",
                             active: false, symbol: "aspectratio")
            frameChip.toolTip = NSLocalizedString("console.chip.frameTooltip", comment: "")
        } else {
            frameChip.isHidden = true
        }

        let visible = status["visible"]?.boolValue ?? false
        visibleChip.update(text: visible
            ? NSLocalizedString("console.chip.visible", comment: "")
            : NSLocalizedString("console.chip.hidden", comment: ""),
                           active: visible,
                           symbol: visible ? "eye.fill" : "eye.slash")

        // 用当前模式而不是功能名做标签：关闭穿透时显示「交互」，避免灰色「穿透」
        // 被误读成功能不可用（与状态栏菜单的「窗口状态：交互 / 穿透」保持一致）。
        let passthrough = status["passthrough"]?.boolValue ?? false
        passthroughChip.update(text: NSLocalizedString(
                                   passthrough ? "console.chip.passthrough" : "console.chip.interactive",
                                   comment: ""),
                               active: true,
                               activeColor: passthrough ? .systemOrange : .systemGreen,
                               symbol: passthrough ? "hand.tap" : "cursorarrow")

        let watching = status["watching"]?.boolValue ?? false
        watchChip.isHidden = !watching
        watchChip.update(text: NSLocalizedString("console.chip.watching", comment: ""),
                         active: watching, activeColor: .systemBlue,
                         symbol: "arrow.triangle.2.circlepath")
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutPreview()
    }

    private func layoutPreview() {
        let box = previewCard.contentView.bounds.size
        guard let item = currentTemplate, box.width > 1, box.height > 1 else { return }
        let size = item.frameSize
        let scale = min(min(1, box.width / max(size.width, 1)),
                        box.height / max(size.height, 1))

        previewWebView.layer?.setAffineTransform(.identity)
        previewWebView.frame = NSRect(x: (box.width - size.width) / 2,
                                      y: (box.height - size.height) / 2,
                                      width: size.width,
                                      height: size.height)
        previewWebView.layer?.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
    }

    // MARK: - 动作

    @objc private func applyTapped() {
        guard let item = currentTemplate else { return }
        onApply?(item)
    }

    @objc private func deleteTapped() {
        guard let item = currentTemplate else { return }
        onDelete?(item)
    }

    @objc private func openTemplatesFolder() {
        NSWorkspace.shared.open(TemplateStore.userTemplatesDirectory())
    }

    // MARK: - 文案

    private func positionText(_ position: WindowPosition?) -> String {
        position?.displayName ?? NSLocalizedString("console.position.auto", comment: "")
    }
}
