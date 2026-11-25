import AppKit
import WebKit
import PinShellCore

/// 控制台右侧详情：模板预览/应用/编辑，或模板库 / MCP / 通用 / 快捷键 / 关于页。
@MainActor
final class ConsoleDetailViewController: NSViewController {
    var onApply: ((TemplateItem) -> Void)?
    var onDelete: ((TemplateItem) -> Void)?
    var onEdit: ((TemplateItem) -> Void)?
    var onOpenLibrary: (() -> Void)?
    var onOpenInstalled: ((String) -> Void)?
    /// 按文件名查询在线目录中的作者；本地模板不在目录中时返回 nil。
    var authorProvider: ((String) -> TemplateLibraryAuthor?)?
    /// 按文件名查询已安装模板的版本号；本地模板不在模板库中时返回 nil。
    var versionProvider: ((String) -> String?)?

    private(set) var currentTemplate: TemplateItem?

    // 模板状态：只在本页显示，不再占用全局状态条。
    private let frameChip = StatusChip()
    private let visibleChip = StatusChip()
    private let passthroughChip = StatusChip()
    private let watchChip = StatusChip()
    private var displayedFile: String?

    private let contentContainer = NSView()
    private let templatePage = ConsoleScrollPage(horizontalInset: ConsoleTheme.Space.pageInset,
                                                 spacing: ConsoleTheme.Space.lg)
    private let emptyPage = NSView()
    /// 服务页在首次打开时才构建，避免打开控制台就创建整套卡片。
    private var pageViews: [ConsolePage: NSView] = [:]

    // MARK: - 模板详情

    /// 预览舞台直接铺满卡片：卡片描边就是唯一边框，中间不再露出一圈白色卡片底。
    private let previewCard = ConsoleCard(
        cornerRadius: ConsoleTheme.Radius.card,
        inset: NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    )
    private let previewStage = ConsoleStageView(cornerRadius: ConsoleTheme.Radius.card,
                                                showsBorder: false)
    private let previewWebView = WKWebView(frame: .zero)
    /// 承载 WebView 的窗口框：负责整窗圆角裁剪，避免直接给 WKWebView 图层加 mask。
    private let previewWindowView = NSView()
    /// 窗口在舞台上的投影（HTML 的 CSS 阴影被 WebView 裁掉，这里补一层原生阴影）。
    private let previewShadowView = PreviewShadowView()
    private var previewHeightConstraint: NSLayoutConstraint?
    /// 当前预览模板的窗口圆角（与 OverlayWindowController 的整窗裁剪保持一致）。
    private var previewRadius: CGFloat = 0

    /// 预览窗口与舞台内容边缘之间留给阴影的空隙。
    private static let previewShadowMargin: CGFloat = 8

    private let titleLabel = NSTextField(labelWithAttributedString:
        ConsoleTheme.Font.tracked("—", font: ConsoleTheme.Font.pageTitle))
    private let subtitleLabel = NSTextField(wrappingLabelWithString: "")
    /// 副标题行：说明文字靠左，模板库版本号右对齐。
    private let subtitleRow = NSStackView()
    private let versionLabel = NSTextField(labelWithString: "")
    private let showingChip = StatusChip()

    private lazy var applyButton = makeConsoleButton(
        NSLocalizedString("console.apply", comment: ""),
        symbol: "pin.fill",
        style: .primary,
        target: self,
        action: #selector(applyTapped))

    private lazy var editButton = makeConsoleButton(
        NSLocalizedString("console.detail.edit", comment: ""),
        symbol: "slider.horizontal.3",
        style: .secondary,
        target: self,
        action: #selector(editTapped))

    private lazy var moreButton = makeIconButton(
        symbol: "ellipsis.circle",
        accessibilityLabel: NSLocalizedString("console.detail.more", comment: ""),
        target: self,
        action: #selector(moreTapped))

    private lazy var fileInfoRow = SettingsRowView(
        title: NSLocalizedString("console.detail.file", comment: ""),
        value: "—",
        accessory: makeIconButton(
            symbol: "folder",
            accessibilityLabel: NSLocalizedString("console.toolbar.folder", comment: ""),
            target: self,
            action: #selector(revealTapped)))

    private lazy var authorButton = makeIconButton(
        symbol: "arrow.up.right.square",
        accessibilityLabel: NSLocalizedString("library.detail.authorPage", comment: ""),
        target: self,
        action: #selector(openAuthorPage))

    private lazy var authorInfoRow = SettingsRowView(
        title: NSLocalizedString("library.detail.author", comment: ""),
        value: "—",
        accessory: authorButton)

    private var currentAuthor: TemplateLibraryAuthor?

    private lazy var sizeInfoRow = SettingsRowView(
        title: NSLocalizedString("console.detail.size", comment: ""),
        value: "—")

    private lazy var positionInfoRow = SettingsRowView(
        title: NSLocalizedString("console.detail.position", comment: ""),
        value: "—")

    private lazy var orderInfoRow = SettingsRowView(
        title: NSLocalizedString("console.detail.order", comment: ""),
        value: "—")

    private let infoGroup = SettingsGroupView(
        title: NSLocalizedString("console.detail.info", comment: ""))
    private var authorSlot: SettingsRowsView.RowSlot?

    override func loadView() {
        let root = ConsoleBackgroundView()
        view = root
        build()
    }

    // MARK: - 装配

    private func build() {
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentContainer)

        NSLayoutConstraint.activate([
            contentContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        buildTemplatePage()
        buildEmptyPage()
        templatePage.pinEdges(to: contentContainer)
        emptyPage.pinEdges(to: contentContainer)
        templatePage.isHidden = true
        emptyPage.isHidden = false
    }

    private func buildTemplatePage() {
        previewWebView.makeTransparent()
        previewStage.translatesAutoresizingMaskIntoConstraints = false
        previewCard.contentView.addSubview(previewStage)
        NSLayoutConstraint.activate([
            previewStage.leadingAnchor.constraint(equalTo: previewCard.contentView.leadingAnchor),
            previewStage.trailingAnchor.constraint(equalTo: previewCard.contentView.trailingAnchor),
            previewStage.topAnchor.constraint(equalTo: previewCard.contentView.topAnchor),
            previewStage.bottomAnchor.constraint(equalTo: previewCard.contentView.bottomAnchor),
        ])
        previewStage.contentView.addSubview(previewShadowView)

        previewWindowView.wantsLayer = true
        previewWindowView.layer?.cornerCurve = .circular
        previewStage.contentView.addSubview(previewWindowView)
        previewWebView.autoresizingMask = [.width, .height]
        previewWindowView.addSubview(previewWebView)

        // 高度跟随模板声明高度；空间不足时可被压缩，保证标题与操作按钮可见
        let height = previewCard.heightAnchor.constraint(equalToConstant: 236)
        height.priority = .defaultHigh
        height.isActive = true
        previewHeightConstraint = height

        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        subtitleLabel.font = ConsoleTheme.Font.pageSubtitle
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.maximumNumberOfLines = 2
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        versionLabel.font = ConsoleTheme.Font.monoMeta
        versionLabel.textColor = .tertiaryLabelColor
        versionLabel.alignment = .right
        versionLabel.setContentHuggingPriority(.required, for: .horizontal)
        versionLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        versionLabel.isHidden = true
        versionLabel.setAccessibilityLabel(
            NSLocalizedString("console.detail.version", comment: ""))

        let subtitleSpacer = NSView()
        subtitleSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        subtitleSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitleRow.orientation = .horizontal
        subtitleRow.alignment = .firstBaseline
        subtitleRow.spacing = ConsoleTheme.Space.xs
        subtitleRow.addArrangedSubview(subtitleLabel)
        subtitleRow.addArrangedSubview(subtitleSpacer)
        subtitleRow.addArrangedSubview(versionLabel)

        showingChip.configure(text: NSLocalizedString("console.detail.showing", comment: ""),
                              symbol: "pin.fill",
                              style: .positive)
        showingChip.isHidden = true

        let headerSpacer = NSView()
        headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let headerRow = NSStackView(views: [titleLabel, showingChip, headerSpacer])
        headerRow.orientation = .horizontal
        headerRow.spacing = 10
        headerRow.alignment = .centerY

        applyButton.keyEquivalent = "\r"

        let actionSpacer = NSView()
        actionSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let actions = NSStackView(views: [applyButton, editButton, actionSpacer, moreButton])
        actions.orientation = .horizontal
        actions.spacing = ConsoleTheme.Space.xs
        actions.alignment = .centerY

        let statusSpacer = NSView()
        statusSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let statusRow = NSStackView(views: [frameChip, visibleChip, passthroughChip,
                                            watchChip, statusSpacer])
        statusRow.orientation = .horizontal
        statusRow.spacing = 6
        statusRow.alignment = .centerY

        infoGroup.addRow(fileInfoRow)
        authorSlot = infoGroup.addRow(authorInfoRow)
        authorSlot?.setHidden(true)
        infoGroup.addRow(sizeInfoRow)
        infoGroup.addRow(positionInfoRow)
        infoGroup.addRow(orderInfoRow)

        let stack = templatePage.stack
        for view in [headerRow, subtitleRow, statusRow, actions, previewCard, infoGroup] {
            stack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        stack.setCustomSpacing(6, after: headerRow)
        stack.setCustomSpacing(10, after: subtitleRow)
        stack.setCustomSpacing(16, after: statusRow)
    }

    private func buildEmptyPage() {
        let browse = makeConsoleButton(
            NSLocalizedString("console.empty.browseLibrary", comment: ""),
            symbol: "square.grid.2x2",
            style: .primary,
            target: self,
            action: #selector(browseLibraryTapped))

        let openFolder = makeConsoleButton(
            NSLocalizedString("console.empty.openFolder", comment: ""),
            symbol: "folder",
            style: .secondary,
            target: self,
            action: #selector(openTemplatesFolder))

        let empty = EmptyStateView(
            symbol: "rectangle.on.rectangle.slash",
            title: NSLocalizedString("console.empty.title", comment: ""),
            message: NSLocalizedString("console.empty.subtitle", comment: ""),
            actions: [browse, openFolder])
        empty.translatesAutoresizingMaskIntoConstraints = false
        emptyPage.addSubview(empty)
        NSLayoutConstraint.activate([
            empty.leadingAnchor.constraint(equalTo: emptyPage.leadingAnchor),
            empty.trailingAnchor.constraint(equalTo: emptyPage.trailingAnchor),
            empty.topAnchor.constraint(equalTo: emptyPage.topAnchor),
            empty.bottomAnchor.constraint(equalTo: emptyPage.bottomAnchor),
        ])
    }

    // MARK: - 页面切换

    private enum Page: Equatable {
        case template
        case empty
        case service(ConsolePage)
    }

    private var currentPage: Page = .empty

    var isShowingLibrary: Bool { currentPage == .service(.library) }

    var isShowingServicePage: Bool {
        if case .service = currentPage { return true }
        return false
    }

    private func show(_ page: Page) {
        currentPage = page
        if case .service(let servicePage) = page {
            templatePage.isHidden = true
            emptyPage.isHidden = true
            hideServicePages(except: servicePage)
            pageViews[servicePage]?.isHidden = false
        } else {
            templatePage.isHidden = page != .template
            emptyPage.isHidden = page != .empty
            hideServicePages()
        }
    }

    private func hideServicePages(except visible: ConsolePage? = nil) {
        for (page, view) in pageViews where page != visible {
            view.isHidden = true
        }
    }

    private func pageView(for page: ConsolePage,
                          service: TemplateLibraryService) -> NSView {
        if let view = pageViews[page] { return view }
        let view: NSView
        switch page {
        case .library:
            let library = ConsoleLibraryView(service: service)
            library.onOpenInstalled = { [weak self] file in
                self?.onOpenInstalled?(file)
            }
            view = library
        case .general:
            view = ConsoleGeneralView(service: service)
        case .shortcuts:
            view = ConsoleShortcutsView()
        case .mcp:
            view = ConsoleMCPView()
        case .cli:
            view = ConsoleCommandLineView()
        case .about:
            view = ConsoleAboutView()
        }
        view.pinEdges(to: contentContainer)
        view.isHidden = true
        pageViews[page] = view
        return view
    }

    func showTemplate(_ item: TemplateItem) {
        currentTemplate = item
        show(.template)

        titleLabel.attributedStringValue = ConsoleTheme.Font.tracked(
            item.name,
            font: ConsoleTheme.Font.pageTitle)
        subtitleLabel.stringValue = item.description
        subtitleLabel.isHidden = item.description.isEmpty

        fileInfoRow.configure(value: item.file)
        refreshLibraryMetadata()
        sizeInfoRow.configure(value: "\(NumberFormat.text(item.size.width))×"
                                    + "\(NumberFormat.text(item.size.height))")
        positionInfoRow.configure(value: positionText(item.spec.position))
        orderInfoRow.configure(value: item.order == Int.max ? "—" : "#\(item.order)")

        // 舞台留白：让 HTML 以其声明高度 1:1 展示；
        // 过高的模板在可视区内缩放，避免把标题和操作挤出首屏。
        let chrome = 2 * ConsoleTheme.Space.stageInset
        let natural = item.size.height + CGFloat(chrome)
        previewHeightConstraint?.constant = min(max(120, natural), 300)
        // 整窗圆角与悬浮窗保持一致。HTML 的窗口阴影会被 WebView 边界裁断，
        // 只在四角留下一圈灰边；按窗口圆角裁剪后才是悬浮窗真实的边缘。
        let radius = CGFloat(max(item.spec.radius ?? 0, 0))
        previewRadius = radius
        previewWindowView.layer?.masksToBounds = radius > 0
        previewShadowView.isHidden = radius <= 0
        previewWebView.loadLocalHTMLFile(item.url)
        updateShowingState()
        view.layoutSubtreeIfNeeded()
        layoutPreview()
    }

    /// 目录加载/刷新完成后，补上当前模板的作者与版本信息。
    func refreshLibraryMetadata() {
        guard let item = currentTemplate else {
            updateAuthor(nil)
            updateVersion(nil)
            return
        }
        updateAuthor(authorProvider?(item.file))
        updateVersion(versionProvider?(item.file))
    }

    private func updateVersion(_ version: String?) {
        versionLabel.stringValue = version.map { "v\($0)" } ?? ""
        versionLabel.isHidden = version == nil
        // 说明为空时这一行由版本号单独撑起，避免整行被隐藏。
        subtitleRow.isHidden = subtitleLabel.isHidden && versionLabel.isHidden
    }

    private func updateAuthor(_ author: TemplateLibraryAuthor?) {
        currentAuthor = author
        guard let author else {
            authorSlot?.setHidden(true)
            authorButton.isHidden = true
            return
        }
        authorInfoRow.configure(value: author.name)
        authorSlot?.setHidden(false)
        authorButton.isHidden = author.url.flatMap(URL.init(string:)) == nil
    }

    func showEmpty() {
        currentTemplate = nil
        updateAuthor(nil)
        updateVersion(nil)
        show(.empty)
    }

    func showPage(_ page: ConsolePage, service: TemplateLibraryService) {
        currentTemplate = nil
        let view = pageView(for: page, service: service)
        show(.service(page))
        (view as? ConsoleServicePage)?.activate()
    }

    /// 官网深链：确保模板库页存在并安装指定模板。
    func installTemplateFromLibrary(id: String,
                                    catalogURL: URL,
                                    service: TemplateLibraryService) async {
        let view = pageView(for: .library, service: service)
        await (view as? ConsoleLibraryView)?.installTemplate(id: id, catalogURL: catalogURL)
    }

    func refreshLibrary() {
        (pageViews[.library] as? ConsoleLibraryView)?.refresh()
    }

    func refreshGeneral() {
        (pageViews[.general] as? ConsoleGeneralView)?.refresh()
    }

    func refreshStatus(_ status: JSONValue) {
        let path = status["file"]?.stringValue
        displayedFile = path.map { ($0 as NSString).lastPathComponent }

        if let frame = status["frame"],
           let width = frame["width"]?.doubleValue,
           let height = frame["height"]?.doubleValue {
            frameChip.isHidden = false
            frameChip.configure(
                text: "\(NSLocalizedString("console.chip.frame", comment: "")) "
                    + "\(NumberFormat.text(width))×\(NumberFormat.text(height))",
                symbol: "aspectratio",
                style: .neutral,
                toolTip: NSLocalizedString("console.chip.frameTooltip", comment: ""))
        } else {
            frameChip.isHidden = true
        }

        let visible = status["visible"]?.boolValue ?? false
        visibleChip.configure(
            text: visible
                ? NSLocalizedString("console.chip.visible", comment: "")
                : NSLocalizedString("console.chip.hidden", comment: ""),
            symbol: visible ? "eye.fill" : "eye.slash",
            style: visible ? .positive : .neutral)

        // 用当前模式而不是功能名做标签：关闭穿透时显示「交互」，避免灰色「穿透」
        // 被误读成功能不可用（与状态栏菜单的「窗口状态：交互 / 穿透」保持一致）。
        let passthrough = status["passthrough"]?.boolValue ?? false
        passthroughChip.configure(
            text: NSLocalizedString(
                passthrough ? "console.chip.passthrough" : "console.chip.interactive",
                comment: ""),
            symbol: passthrough ? "hand.tap" : "cursorarrow",
            style: passthrough ? .warning : .positive)

        let watching = status["watching"]?.boolValue ?? false
        watchChip.isHidden = !watching
        watchChip.configure(
            text: NSLocalizedString("console.chip.watching", comment: ""),
            symbol: "arrow.triangle.2.circlepath",
            style: .accent)

        updateShowingState()
    }

    private func updateShowingState() {
        guard let item = currentTemplate, let file = displayedFile else {
            showingChip.isHidden = true
            return
        }
        showingChip.isHidden = item.url.lastPathComponent != file
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutPreview()
    }

    private func layoutPreview() {
        let box = previewStage.contentView.bounds.size
        guard let item = currentTemplate, box.width > 1, box.height > 1 else { return }
        let size = item.frameSize
        // 留出阴影的绘制空隙，避免被舞台的圆角遮罩裁掉。
        let margin = previewRadius > 0 ? Self.previewShadowMargin : 0
        let available = NSSize(width: max(box.width - 2 * margin, 1),
                               height: max(box.height - 2 * margin, 1))
        let scale = min(min(1, available.width / max(size.width, 1)),
                        available.height / max(size.height, 1))

        // 用 pageZoom 而不是图层 transform：WKWebView 只绘制 visibleRect 内的内容，
        // 图层缩放会把未绘制（负坐标）的部分一起裁掉，预览只剩窗口上半截。
        let scaled = NSSize(width: size.width * scale, height: size.height * scale)
        let frame = NSRect(x: (box.width - scaled.width) / 2,
                           y: (box.height - scaled.height) / 2,
                           width: scaled.width,
                           height: scaled.height)
        previewWindowView.frame = frame
        previewWebView.frame = previewWindowView.bounds
        previewWebView.pageZoom = scale
        let corner = previewRadius * scale
        previewWindowView.layer?.cornerRadius = corner
        previewShadowView.frame = frame.insetBy(dx: -PreviewShadowView.bleed,
                                                dy: -PreviewShadowView.bleed)
        previewShadowView.cornerRadius = corner
    }

    // MARK: - 动作

    @objc private func applyTapped() {
        guard let item = currentTemplate else { return }
        onApply?(item)
    }

    @objc private func editTapped() {
        guard let item = currentTemplate else { return }
        onEdit?(item)
    }

    @objc private func deleteTapped() {
        guard let item = currentTemplate else { return }
        onDelete?(item)
    }

    @objc private func revealTapped() {
        guard let item = currentTemplate else { return }
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    @objc private func openAuthorPage() {
        guard let url = currentAuthor?.url.flatMap(URL.init(string:)) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func moreTapped() {
        let menu = NSMenu()

        let reveal = NSMenuItem(title: NSLocalizedString("console.toolbar.folder", comment: ""),
                                action: #selector(revealTapped), keyEquivalent: "")
        reveal.target = self
        reveal.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        menu.addItem(reveal)

        menu.addItem(.separator())

        let delete = NSMenuItem(title: NSLocalizedString("console.detail.delete", comment: ""),
                                action: #selector(deleteTapped), keyEquivalent: "")
        delete.target = self
        delete.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        menu.addItem(delete)

        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: moreButton.bounds.height + 4),
                   in: moreButton)
    }

    @objc private func browseLibraryTapped() {
        onOpenLibrary?()
    }

    @objc private func openTemplatesFolder() {
        NSWorkspace.shared.open(TemplateStore.userTemplatesDirectory())
    }

    // MARK: - 文案

    private func positionText(_ position: WindowPosition?) -> String {
        position?.displayName ?? NSLocalizedString("console.position.auto", comment: "")
    }
}

// MARK: - 预览投影

/// 只绘制窗口外侧的柔和投影。
///
/// 直接用 CALayer.shadow 会被 AppKit 重置（且父图层裁剪会截断光晕），
/// 这里用 NSShadow 在窗口形状外侧画一层，用 even-odd 裁掉内部避免透色。
private final class PreviewShadowView: NSView {
    /// 四周预留的绘制空间（大于模糊半径 + 偏移，保证光晕不出界）。
    static let bleed: CGFloat = 16

    var cornerRadius: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard cornerRadius > 0, let context = NSGraphicsContext.current else { return }
        let shapeRect = bounds.insetBy(dx: Self.bleed, dy: Self.bleed)
        guard shapeRect.width > 2, shapeRect.height > 2 else { return }
        let shape = NSBezierPath(roundedRect: shapeRect,
                                 xRadius: cornerRadius,
                                 yRadius: cornerRadius)

        let outside = NSBezierPath(rect: bounds)
        outside.append(shape)
        outside.windingRule = .evenOdd

        context.saveGraphicsState()
        outside.addClip()

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.26)
        shadow.shadowBlurRadius = 10
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.set()

        NSColor.black.setFill()
        shape.fill()
        context.restoreGraphicsState()
    }
}
