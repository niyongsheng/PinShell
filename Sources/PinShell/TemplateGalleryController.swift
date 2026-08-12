import AppKit
import WebKit

/// 模板库窗口：模板卡片列表 + 实时预览 + 底部控制条（穿透/重置/当前文件）。
/// 普通层级窗口（非 overlay），录屏前 ⌘W 关闭即可，不进入录制画面。
final class TemplateGalleryController: NSObject, NSWindowDelegate {
    /// 预览区固定尺寸（与约束常量一致；布局未完成时不能依赖 bounds）
    private static let previewSize = NSSize(width: 428, height: 120)

    private let windowController: OverlayWindowController
    private var templates: [TemplateItem]   // 每次打开时重载（用户可能已编辑/新增模板）
    private(set) var window: NSWindow!

    private let previewBox = NSView()
    private let previewWebView = WKWebView(frame: .zero)
    private let listStack = NSStackView()
    private let passthroughSwitch = NSSwitch()
    private let currentFileLabel = NSTextField(labelWithString: "—")
    private var cards: [TemplateCardView] = []
    private var selectedIndex: Int?

    init(windowController: OverlayWindowController) {
        self.windowController = windowController
        self.templates = []
        super.init()
        buildWindow()
        buildLayout()
        previewWebView.makeTransparent()   // 与 overlay 同一配方（见 WKWebView.makeTransparent）
        syncControls()
        NotificationCenter.default.addObserver(self, selector: #selector(passthroughChanged(_:)),
                                               name: .pinshellPassthroughChanged, object: nil)
        // 模板清单与选中态在每次 show() 时重建（用户可能已编辑模板目录）
    }

    // MARK: - 装配

    private func buildWindow() {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 440),
                           styleMask: [.titled, .closable, .fullSizeContentView],
                           backing: .buffered, defer: false)
        win.title = NSLocalizedString("gallery.title", comment: "")
        win.titlebarAppearsTransparent = true
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.backgroundColor = .clear
        window = win
        // 液态玻璃背景：系统 .popover 材质在 macOS 26 上自动呈现玻璃质感
        let glass = NSVisualEffectView(frame: win.contentView!.bounds)
        glass.material = .popover
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.autoresizingMask = [.width, .height]
        win.contentView?.addSubview(glass, positioned: .below, relativeTo: nil)
    }

    private func buildLayout() {
        let content = window.contentView!

        // 预览区：透明容器 + logo 红细描边 —— 模板卡直接浮在窗口玻璃上（所见即所得）
        previewBox.wantsLayer = true
        previewBox.layer?.cornerRadius = 18
        previewBox.layer?.borderWidth = 1
        previewBox.layer?.borderColor = NSColor.pinshellBrandRed.withAlphaComponent(0.8).cgColor
        previewBox.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.10).cgColor
        previewBox.addSubview(previewWebView)

        // 模板卡片列表（内容由 reloadTemplates 填充，支持打开时刷新）
        listStack.orientation = .vertical
        listStack.alignment = .width
        listStack.spacing = 8
        listStack.distribution = .fill

        // 底部控制条
        let controlBar = buildControlBar()

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .centerX
        root.spacing = 12
        // fullSizeContentView：顶部留出标题栏空间（内容延伸到玻璃下）
        root.edgeInsets = NSEdgeInsets(top: 44, left: 16, bottom: 16, right: 16)
        root.addArrangedSubview(previewBox)
        root.addArrangedSubview(listStack)
        root.addArrangedSubview(controlBar)
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            previewBox.widthAnchor.constraint(equalToConstant: Self.previewSize.width),
            previewBox.heightAnchor.constraint(equalToConstant: Self.previewSize.height),
            controlBar.widthAnchor.constraint(equalToConstant: Self.previewSize.width),
        ])
    }

    private func buildControlBar() -> NSView {
        let switchLabel = NSTextField(labelWithString: NSLocalizedString("gallery.passthrough", comment: ""))
        switchLabel.font = .systemFont(ofSize: 13)
        switchLabel.textColor = .labelColor

        passthroughSwitch.controlSize = .small
        passthroughSwitch.target = self
        passthroughSwitch.action = #selector(passthroughToggled(_:))

        let openFolder = NSButton(title: NSLocalizedString("gallery.openFolder", comment: ""),
                                  target: self, action: #selector(openTemplatesFolder(_:)))
        openFolder.bezelStyle = .rounded
        openFolder.controlSize = .small
        openFolder.font = .systemFont(ofSize: 12)

        let resetButton = NSButton(title: NSLocalizedString("gallery.resetPosition", comment: ""),
                                   target: self, action: #selector(resetPosition(_:)))
        resetButton.bezelStyle = .rounded
        resetButton.controlSize = .small
        resetButton.font = .systemFont(ofSize: 12)

        currentFileLabel.font = .systemFont(ofSize: 11)
        currentFileLabel.textColor = .secondaryLabelColor
        currentFileLabel.lineBreakMode = .byTruncatingMiddle
        currentFileLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.spacing = 8
        bar.alignment = .centerY
        bar.addArrangedSubview(passthroughSwitch)
        bar.addArrangedSubview(switchLabel)
        bar.addArrangedSubview(NSView())   // 弹性间隔
        bar.addArrangedSubview(openFolder)
        bar.addArrangedSubview(resetButton)
        bar.addArrangedSubview(currentFileLabel)
        currentFileLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 110).isActive = true
        return bar
    }

    // MARK: - 交互

    func show() {
        reloadTemplates()          // 每次打开重载：用户可能已编辑/新增模板
        selectInitialTemplate()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 重建模板卡片列表（模板清单来自用户目录，改动即时生效）
    private func reloadTemplates() {
        templates = TemplateStore.load()
        selectedIndex = nil
        listStack.arrangedSubviews.forEach {
            listStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        cards.removeAll()
        for (index, item) in templates.enumerated() {
            let card = TemplateCardView(item: item,
                                        onSelect: { [weak self] _ in self?.select(at: index) },
                                        onApply: { [weak self] item in self?.apply(item) })
            card.heightAnchor.constraint(equalToConstant: 48).isActive = true
            listStack.addArrangedSubview(card)
            cards.append(card)
        }
    }

    private func selectInitialTemplate() {
        // 当前正在显示内置模板 → 选中它；否则选第一个
        if let current = windowController.currentURL?.standardizedFileURL,
           let idx = templates.firstIndex(where: {
               TemplateStore.fileURL(for: $0)?.standardizedFileURL == current
           }) {
            select(at: idx)
        } else {
            select(at: 0)
        }
    }

    private func select(at index: Int) {
        guard templates.indices.contains(index) else { return }
        selectedIndex = index
        for (i, card) in cards.enumerated() { card.setSelected(i == index) }
        showPreview(for: templates[index])
    }

    private func showPreview(for item: TemplateItem) {
        // 用固定尺寸而非当前 bounds：首次打开时 Auto Layout 尚未布局，bounds 为 0
        let box = Self.previewSize
        // 等比缩放适配预览框：任意用户模板尺寸都能完整预览（不依赖模板恰好 ≤ 428×120）
        let size = item.frameSize
        let scale = min(min(1, box.width / max(size.width, 1)), box.height / max(size.height, 1))
        previewWebView.frame = NSRect(x: (box.width - size.width) / 2,
                                      y: (box.height - size.height) / 2,
                                      width: size.width,
                                      height: size.height)
        previewWebView.layer?.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        if let url = TemplateStore.fileURL(for: item) {
            previewWebView.loadLocalHTMLFile(url)
        }
    }

    private func apply(_ item: TemplateItem) {
        guard let url = TemplateStore.fileURL(for: item) else { return }
        windowController.loadHTML(url)
        windowController.applyTemplateSize(item.frameSize)
        window.close()   // 应用后自动收起：录屏时画面里不留模板库窗口
    }

    private func syncControls() {
        passthroughSwitch.state = AppState.passthroughEnabled ? .on : .off
        currentFileLabel.stringValue = windowController.currentURL?.lastPathComponent ?? "—"
        currentFileLabel.toolTip = windowController.currentURL?.path
    }

    @objc private func passthroughToggled(_ sender: NSSwitch) {
        windowController.setPassthrough(sender.state == .on)
    }

    @objc private func resetPosition(_ sender: Any?) {
        windowController.resetToDefaultFrame()
    }

    /// 在 Finder 中打开模板目录（选中当前模板文件，未选中则打开整个目录）
    @objc private func openTemplatesFolder(_ sender: Any?) {
        let dir = TemplateStore.userTemplatesDirectory()
        if let idx = selectedIndex, templates.indices.contains(idx),
           let url = TemplateStore.fileURL(for: templates[idx]) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(dir)
        }
    }

    @objc private func passthroughChanged(_ notification: Notification) {
        // 通知只作变化信号，状态一律从 AppState 读（单一事实来源）
        passthroughSwitch.state = AppState.passthroughEnabled ? .on : .off
    }
}

// MARK: - 模板卡片

/// 卡片：名称 + 描述 + 系统原生「应用」按钮；点击选中（柔和蓝调）
final class TemplateCardView: NSView {
    private let item: TemplateItem
    private let onSelect: (TemplateItem) -> Void
    private let onApply: (TemplateItem) -> Void
    private let nameLabel = NSTextField(labelWithString: "")

    init(item: TemplateItem, onSelect: @escaping (TemplateItem) -> Void,
         onApply: @escaping (TemplateItem) -> Void) {
        self.item = item
        self.onSelect = onSelect
        self.onApply = onApply
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.masksToBounds = true
        // 半透明磨砂卡（透出窗口玻璃），深浅色自适应
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.55).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func build() {
        nameLabel.stringValue = item.name
        nameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        nameLabel.textColor = .labelColor

        let desc = NSTextField(labelWithString: item.description)
        desc.font = .systemFont(ofSize: 11)
        desc.textColor = .secondaryLabelColor

        // 系统原生按钮：macOS 26 上呈现玻璃胶囊，去掉纯蓝填充
        let apply = NSButton(title: NSLocalizedString("gallery.apply", comment: ""),
                             target: self, action: #selector(applyTapped))
        apply.bezelStyle = .rounded
        apply.controlSize = .small
        apply.font = .systemFont(ofSize: 12, weight: .medium)
        apply.setContentHuggingPriority(.required, for: .horizontal)

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        desc.translatesAutoresizingMaskIntoConstraints = false
        apply.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)
        addSubview(desc)
        addSubview(apply)
        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            desc.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            desc.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            desc.trailingAnchor.constraint(lessThanOrEqualTo: apply.leadingAnchor, constant: -10),
            apply.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            apply.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        // 不用手势识别器：父视图的 NSClickGestureRecognizer 会拦截子按钮的点击
    }

    func setSelected(_ selected: Bool) {
        // 柔和选中态：1px 强调描边 + 10% 蓝调 + 标题变强调色（替代生硬的 2px 蓝框）
        layer?.borderWidth = 1
        layer?.borderColor = (selected
            ? NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor
            : NSColor.separatorColor.cgColor)
        layer?.backgroundColor = (selected
            ? NSColor.controlAccentColor.withAlphaComponent(0.10).cgColor
            : NSColor.windowBackgroundColor.withAlphaComponent(0.55).cgColor)
        nameLabel.textColor = selected ? .controlAccentColor : .labelColor
    }

    // 点击卡片（非按钮区域）→ 选中；按钮的点击由按钮自己处理（hitTest 直达）
    override func mouseDown(with event: NSEvent) {
        onSelect(item)
    }

    // 文本标签不拦截点击：落在文本上的鼠标事件视为卡片点击
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit is NSTextField ? self : hit
    }

    @objc private func applyTapped() { onApply(item) }
}
