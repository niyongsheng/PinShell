import AppKit
import PinShellCore

/// 控制台左侧栏：搜索、模板列表与服务入口。
final class ConsoleSidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSMenuDelegate {
    var onSelectTemplate: ((TemplateItem) -> Void)?
    var onSelectPage: ((ConsolePage) -> Void)?
    var onApplyTemplate: ((TemplateItem) -> Void)?
    var onEditTemplate: ((TemplateItem) -> Void)?
    var onDeleteTemplate: ((TemplateItem) -> Void)?

    private let searchField = NSSearchField()
    private let searchEmptyLabel = NSTextField(labelWithString: "")
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private var rows: [Row] = []
    private var allTemplates: [TemplateItem] = []
    private var selectedTemplateURL: URL?
    private var appliedTemplateURL: URL?
    private var libraryUpdateCount = 0
    private var contextTemplate: TemplateItem?
    private var suppressSelectionCallback = false

    private static let sectionCellID = NSUserInterfaceItemIdentifier("PinShell.Sidebar.Section")
    private static let rowCellID = NSUserInterfaceItemIdentifier("PinShell.Sidebar.Row")

    private enum Row {
        case section(String)
        case template(TemplateItem)
        case page(ConsolePage)

        var isSection: Bool {
            if case .section = self { return true }
            return false
        }
    }

    override func loadView() {
        let root = NSVisualEffectView()
        root.material = .sidebar
        root.blendingMode = .behindWindow
        root.state = .followsWindowActiveState
        view = root
        build()
    }

    // MARK: - 装配

    private func build() {
        searchField.placeholderString = NSLocalizedString("console.search", comment: "")
        searchField.sendsSearchStringImmediately = true
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.controlSize = .large
        searchField.font = .systemFont(ofSize: 13)
        searchField.translatesAutoresizingMaskIntoConstraints = false

        searchEmptyLabel.stringValue = NSLocalizedString("console.sidebar.noResults", comment: "")
        searchEmptyLabel.font = ConsoleTheme.Font.caption
        searchEmptyLabel.textColor = .secondaryLabelColor
        searchEmptyLabel.alignment = .center
        searchEmptyLabel.isHidden = true
        searchEmptyLabel.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .sourceList
        tableView.rowHeight = ConsoleTheme.Space.sidebarRowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.allowsEmptySelection = false
        tableView.floatsGroupRows = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(doubleClicked)

        let contextMenu = NSMenu()
        contextMenu.delegate = self
        tableView.menu = contextMenu

        scrollView.documentView = tableView
        // 侧栏不显示滚动条：内容溢出时仍可用滚轮/触控板滚动，
        // 也避免 legacy 样式下滚动条在 vibrancy 背景上过于抢眼。
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(searchField)
        view.addSubview(scrollView)
        view.addSubview(searchEmptyLabel)
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            searchEmptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            searchEmptyLabel.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 24),
            searchEmptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor,
                                                      constant: 12),
            searchEmptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor,
                                                       constant: -12),
        ])
    }

    // MARK: - 数据

    func reloadTemplates(selecting url: URL?) {
        if let url { selectedTemplateURL = url }
        let target = selectedTemplateURL
        allTemplates = TemplateStore.load()
        reloadRowsAndSelect(target: target)
    }

    /// 重建行并恢复选中。reloadData 会临时改动选中行并回调，
    /// 期间必须屏蔽回调，避免把 selectedTemplateURL 改写成第一行。
    private func reloadRowsAndSelect(target: URL?, notify: Bool = true) {
        let wasSuppressed = suppressSelectionCallback
        suppressSelectionCallback = true
        defer { suppressSelectionCallback = wasSuppressed }
        rebuildRows()
        selectCurrentRow(target: target, notify: notify)
    }

    /// 目录内容变化后的静默刷新：保持当前选中行，不触发页面切换回调。
    @discardableResult
    func refreshTemplatesKeepingSelection() -> [TemplateItem] {
        let selected = selectionKind()
        let wasSuppressed = suppressSelectionCallback
        // reloadData 会临时自动选中第一行并回调；期间必须屏蔽，否则详情页会被切走。
        suppressSelectionCallback = true
        allTemplates = TemplateStore.load()
        rebuildRows()
        restoreSelection(selected)
        suppressSelectionCallback = wasSuppressed
        return allTemplates
    }

    private enum SelectionKind: Equatable {
        case template(URL)
        case page(ConsolePage)
        case none
    }

    private func selectionKind() -> SelectionKind {
        let row = tableView.selectedRow
        guard rows.indices.contains(row) else { return .none }
        switch rows[row] {
        case .template(let item): return .template(item.url)
        case .page(let page): return .page(page)
        case .section: return .none
        }
    }

    private func restoreSelection(_ kind: SelectionKind) {
        guard let index = rowIndex(for: kind) else { return }
        select(row: index, notify: false)
    }

    private func rowIndex(for kind: SelectionKind) -> Int? {
        switch kind {
        case .template(let url):
            return rows.firstIndex { row in
                guard case .template(let item) = row else { return false }
                return item.url.standardizedFileURL == url.standardizedFileURL
            }
        case .page(let page):
            return rows.firstIndex { row in
                guard case .page(let candidate) = row else { return false }
                return candidate == page
            }
        case .none:
            return nil
        }
    }

    private func firstTemplateIndex() -> Int? {
        rows.firstIndex { if case .template = $0 { return true }; return false }
    }

    /// 选中指定行；notify 为 true 时触发页面切换回调。
    private func select(row index: Int, notify: Bool) {
        let wasSuppressed = suppressSelectionCallback
        suppressSelectionCallback = true
        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        tableView.scrollRowToVisible(index)
        suppressSelectionCallback = wasSuppressed
        if case .template(let item) = rows[index] {
            selectedTemplateURL = item.url
        }
        if notify { notifySelection() }
    }

    private func select(kind: SelectionKind, notify: Bool = true) {
        guard let index = rowIndex(for: kind) else { return }
        select(row: index, notify: notify)
    }

    /// 把当前选中行分发给详情页；搜索过滤未改变选中项时可跳过。
    private func notifySelection() {
        let row = tableView.selectedRow
        guard rows.indices.contains(row) else { return }
        switch rows[row] {
        case .template(let item):
            selectedTemplateURL = item.url
            onSelectTemplate?(item)
        case .page(let page):
            onSelectPage?(page)
        case .section:
            break
        }
    }

    func selectFirstTemplate() {
        guard let index = firstTemplateIndex() else { return }
        select(row: index, notify: true)
    }

    func select(_ page: ConsolePage) {
        select(kind: .page(page))
    }

    /// 标记当前悬浮窗正在显示的模板。重建 cell 以保证稍后创建的复用 cell
    /// 也带上图钉状态；期间屏蔽选中回调并恢复原选中行。
    func updateAppliedTemplate(_ url: URL?) {
        let standardized = url?.standardizedFileURL
        guard standardized != appliedTemplateURL else { return }

        // 刷新整张表，让稍后创建的 cell 也能带上正确的图钉状态；
        // reloadData 会临时改动选中行并回调，期间必须屏蔽回调。
        let kind = selectionKind()
        let wasSuppressed = suppressSelectionCallback
        suppressSelectionCallback = true
        appliedTemplateURL = standardized
        tableView.reloadData()
        if case .none = kind {
            // 不恢复空选中
        } else {
            restoreSelection(kind)
        }
        suppressSelectionCallback = wasSuppressed
    }

    private func isApplied(_ item: TemplateItem) -> Bool {
        guard let appliedTemplateURL else { return false }
        // 悬浮窗可能加载同名的另一份副本；先按完整路径匹配，再按文件名兜底
        return item.url.standardizedFileURL == appliedTemplateURL
            || item.url.lastPathComponent == appliedTemplateURL.lastPathComponent
    }

    func updateLibraryBadge(_ count: Int) {
        guard count != libraryUpdateCount else { return }
        let kind = selectionKind()
        let wasSuppressed = suppressSelectionCallback
        suppressSelectionCallback = true
        libraryUpdateCount = count
        if let index = rowIndex(for: .page(.library)) {
            tableView.reloadData(forRowIndexes: IndexSet(integer: index),
                                 columnIndexes: IndexSet(integer: 0))
            restoreSelection(kind)
        }
        suppressSelectionCallback = wasSuppressed
    }

    /// 打开控制台时把焦点交给列表，搜索框不抢焦点（与系统设置一致）。
    func focusList() {
        view.window?.makeFirstResponder(tableView)
    }

    var hasTemplates: Bool { !allTemplates.isEmpty }

    var isLibrarySelected: Bool {
        selectionKind() == .page(.library)
    }

    private var query: String {
        searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func filteredTemplates() -> [TemplateItem] {
        let q = query
        guard !q.isEmpty else { return allTemplates }
        return allTemplates.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || $0.description.localizedCaseInsensitiveContains(q)
                || $0.file.localizedCaseInsensitiveContains(q)
        }
    }

    private func rebuildRows() {
        let templates = filteredTemplates()
        rows = [.section(NSLocalizedString("console.sidebar.templates", comment: ""))]
        rows.append(contentsOf: templates.map(Row.template))
        rows.append(.section(NSLocalizedString("console.sidebar.online", comment: "")))
        rows.append(.page(.library))
        rows.append(.section(NSLocalizedString("console.sidebar.settings", comment: "")))
        rows.append(.page(.general))
        rows.append(.page(.shortcuts))
        rows.append(.section(NSLocalizedString("console.sidebar.services", comment: "")))
        rows.append(.page(.mcp))
        rows.append(.page(.cli))
        rows.append(.page(.about))
        tableView.reloadData()
        searchEmptyLabel.isHidden = query.isEmpty || !templates.isEmpty
    }

    private func selectCurrentRow(target: URL? = nil, notify: Bool = true) {
        let selectedURL = target ?? selectedTemplateURL
        // 先按完整路径匹配；悬浮窗可能加载的是仓库/别处的同名副本，再按文件名兜底
        let exact = rows.firstIndex { row in
            if case .template(let item) = row {
                return item.url.standardizedFileURL == selectedURL?.standardizedFileURL
            }
            return false
        }
        let byName = rows.firstIndex { row in
            guard case .template(let item) = row,
                  let selected = selectedURL else { return false }
            return item.url.lastPathComponent == selected.lastPathComponent
        }
        guard let targetIndex = exact ?? byName ?? firstTemplateIndex() else {
            tableView.deselectAll(nil)
            return
        }
        select(row: targetIndex, notify: notify)
    }

    private var selectedTemplate: TemplateItem? {
        let row = tableView.selectedRow
        guard rows.indices.contains(row), case .template(let item) = rows[row] else { return nil }
        return item
    }

    // MARK: - 交互

    @objc private func doubleClicked() {
        guard let item = selectedTemplate else { return }
        onApplyTemplate?(item)
    }

    // MARK: - 右键菜单

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = tableView.clickedRow
        guard rows.indices.contains(row), case .template(let item) = rows[row] else {
            contextTemplate = nil
            return
        }
        contextTemplate = item
        if tableView.selectedRow != row {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }

        let applyItem = NSMenuItem(title: NSLocalizedString("console.sidebar.apply", comment: ""),
                                   action: #selector(contextApply), keyEquivalent: "")
        applyItem.target = self
        menu.addItem(applyItem)

        let editItem = NSMenuItem(title: NSLocalizedString("console.sidebar.edit", comment: ""),
                                  action: #selector(contextEdit), keyEquivalent: "")
        editItem.target = self
        menu.addItem(editItem)

        menu.addItem(.separator())

        let deleteItem = NSMenuItem(title: NSLocalizedString("console.sidebar.delete", comment: ""),
                                    action: #selector(contextDelete), keyEquivalent: "")
        deleteItem.target = self
        menu.addItem(deleteItem)
    }

    @objc private func contextApply() {
        if let item = contextTemplate { onApplyTemplate?(item) }
    }

    @objc private func contextEdit() {
        if let item = contextTemplate { onEditTemplate?(item) }
    }

    @objc private func contextDelete() {
        if let item = contextTemplate { onDeleteTemplate?(item) }
    }

    func controlTextDidChange(_ obj: Notification) {
        searchChanged()
    }

    @objc private func searchChanged() {
        let previous = selectedTemplateURL
        reloadRowsAndSelect(target: previous, notify: false)
        // 当前模板仍在过滤结果中时详情页无需重载；只有被迫改选时才通知。
        if selectedTemplateURL?.standardizedFileURL != previous?.standardizedFileURL {
            notifySelection()
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        rows[row].isSection
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        !rows[row].isSection
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        rows[row].isSection
            ? ConsoleTheme.Space.sidebarSectionHeight
            : ConsoleTheme.Space.sidebarRowHeight
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .section(let title):
            let cell = sectionCell()
            cell.textField?.stringValue = title
            return cell

        case .template(let item):
            let cell = rowCell()
            cell.configure(symbol: "rectangle.on.rectangle",
                           title: item.name,
                           trailing: nil,
                           applied: isApplied(item))
            cell.toolTip = "\(item.name) · "
                + "\(NumberFormat.text(item.size.width, fractionDigits: 0))×"
                + "\(NumberFormat.text(item.size.height, fractionDigits: 0))"
            return cell

        case .page(let page):
            let cell = rowCell()
            let badge = page == .library && libraryUpdateCount > 0
                ? "\(libraryUpdateCount)" : nil
            if let asset = page.iconAsset {
                cell.configure(asset: asset, title: page.title, trailing: badge)
            } else {
                cell.configure(symbol: page.symbol, title: page.title, trailing: badge)
            }
            return cell
        }
    }

    private func sectionCell() -> NSTableCellView {
        if let cell = tableView.makeView(withIdentifier: Self.sectionCellID,
                                         owner: self) as? NSTableCellView {
            return cell
        }
        let cell = NSTableCellView()
        cell.identifier = Self.sectionCellID
        let label = NSTextField(labelWithString: "")
        label.font = ConsoleTheme.Font.sidebarSection
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -5),
        ])
        return cell
    }

    private func rowCell() -> SidebarCellView {
        if let cell = tableView.makeView(withIdentifier: Self.rowCellID,
                                         owner: self) as? SidebarCellView {
            return cell
        }
        let cell = SidebarCellView()
        cell.identifier = Self.rowCellID
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !suppressSelectionCallback else { return }
        notifySelection()
    }

}

// MARK: - 侧栏单元格

private final class SidebarCellView: NSTableCellView {
    private let iconContainer = NSView()
    private let symbolView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let trailingLabel = NSTextField(labelWithString: "")
    private let appliedPin = NSImageView()
    private var isApplied = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func build() {
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: 22),
            iconContainer.heightAnchor.constraint(equalToConstant: 22),
        ])

        symbolView.imageScaling = .scaleProportionallyDown
        symbolView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            symbolView.widthAnchor.constraint(equalToConstant: 20),
            symbolView.heightAnchor.constraint(equalToConstant: 20),
        ])

        titleLabel.font = ConsoleTheme.Font.sidebarItem
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        trailingLabel.font = ConsoleTheme.Font.sidebarBadge
        trailingLabel.textColor = .tertiaryLabelColor
        trailingLabel.alignment = .right
        trailingLabel.setContentHuggingPriority(.required, for: .horizontal)
        trailingLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        trailingLabel.translatesAutoresizingMaskIntoConstraints = false

        appliedPin.imageScaling = .scaleProportionallyDown
        appliedPin.translatesAutoresizingMaskIntoConstraints = false
        appliedPin.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold))
        appliedPin.isHidden = true
        appliedPin.toolTip = NSLocalizedString("console.detail.showing", comment: "")
        appliedPin.setAccessibilityElement(true)
        appliedPin.setAccessibilityRole(.image)
        appliedPin.setAccessibilityLabel(NSLocalizedString("console.detail.showing", comment: ""))

        iconContainer.addSubview(symbolView)
        addSubview(iconContainer)
        addSubview(titleLabel)
        addSubview(trailingLabel)
        addSubview(appliedPin)

        NSLayoutConstraint.activate([
            iconContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconContainer.centerYAnchor.constraint(equalTo: centerYAnchor),

            symbolView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            symbolView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingLabel.leadingAnchor, constant: -8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: appliedPin.leadingAnchor, constant: -8),

            trailingLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            trailingLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            appliedPin.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            appliedPin.centerYAnchor.constraint(equalTo: centerYAnchor),
            appliedPin.widthAnchor.constraint(equalToConstant: 12),
            appliedPin.heightAnchor.constraint(equalToConstant: 12),
        ])
        updatePinTint()
    }

    private static let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 17,
                                                                         weight: .medium)
    private static var symbolCache: [String: NSImage] = [:]

    private static func symbolImage(named name: String) -> NSImage? {
        if let cached = symbolCache[name] { return cached }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfiguration)
        symbolCache[name] = image
        return image
    }

    /// bundle 内的 template PNG（如 MCP 标志）：黑色蒙版，随选中态/深浅色染色。
    /// NSImage(named:) 自带缓存，无需再包一层。
    private static func assetImage(named name: String) -> NSImage? {
        guard let image = NSImage(named: name) else { return nil }
        image.isTemplate = true
        return image
    }

    func configure(symbol: String, title: String, trailing: String?, applied: Bool = false) {
        configure(image: Self.symbolImage(named: symbol),
                  title: title,
                  trailing: trailing,
                  applied: applied)
    }

    func configure(asset: String, title: String, trailing: String?, applied: Bool = false) {
        configure(image: Self.assetImage(named: asset),
                  title: title,
                  trailing: trailing,
                  applied: applied)
    }

    private func configure(image: NSImage?,
                           title: String,
                           trailing: String?,
                           applied: Bool) {
        symbolView.image = image
        titleLabel.stringValue = title
        trailingLabel.stringValue = trailing ?? ""
        trailingLabel.isHidden = trailing == nil
        setApplied(applied)
        applyColors()
    }

    func setApplied(_ applied: Bool) {
        isApplied = applied
        appliedPin.isHidden = !applied
        updatePinTint()
    }

    private func updatePinTint() {
        appliedPin.contentTintColor = backgroundStyle == .emphasized
            ? .alternateSelectedControlTextColor
            : ConsoleTheme.Color.accent
    }

    private func applyColors() {
        let emphasized = backgroundStyle == .emphasized
        titleLabel.textColor = emphasized ? .alternateSelectedControlTextColor : .labelColor
        trailingLabel.textColor = emphasized ? .alternateSelectedControlTextColor : .tertiaryLabelColor
        symbolView.contentTintColor = emphasized ? .alternateSelectedControlTextColor : .labelColor
        updatePinTint()
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { applyColors() }
    }
}
