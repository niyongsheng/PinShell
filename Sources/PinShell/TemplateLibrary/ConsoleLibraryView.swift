import AppKit
import PinShellCore

/// Console 的“在线模板库”页：catalog 列表、搜索/分类、安装/更新/忽略。
@MainActor
final class ConsoleLibraryView: NSView, NSSearchFieldDelegate {
    private let service: TemplateLibraryService

    var onOpenInstalled: ((String) -> Void)?

    private lazy var refreshButton: NSButton = {
        let button = NSButton(title: NSLocalizedString("library.refresh", comment: ""),
                              target: self, action: #selector(refreshTapped))
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.font = .systemFont(ofSize: 11.5, weight: .medium)
        button.imagePosition = .imageLeading
        button.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }()

    private lazy var header = PageHeader(
        symbol: "square.grid.2x2",
        title: NSLocalizedString("library.title", comment: ""),
        subtitle: NSLocalizedString("library.subtitle", comment: ""),
        accessory: refreshButton)

    private let searchField = NSSearchField()
    private let categoryPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let updatedLabel = NSTextField(labelWithString: "")
    private let noticeContainer = NSView()
    private let noticeView = ConsoleNoticeView(tone: .warning)
    private var noticeHeightConstraint: NSLayoutConstraint?
    private let scrollView = NSScrollView()
    private let rowsStack = FlippedStackView()
    private let loadingIndicator = NSProgressIndicator()

    private lazy var retryButton = makeConsoleButton(
        NSLocalizedString("library.retry", comment: ""),
        symbol: "arrow.clockwise",
        style: .primary,
        target: self,
        action: #selector(refreshTapped))

    private lazy var openFolderButton = makeConsoleButton(
        NSLocalizedString("console.empty.openFolder", comment: ""),
        symbol: "folder",
        style: .secondary,
        target: self,
        action: #selector(openTemplatesFolder))

    private lazy var emptyStateView = EmptyStateView(
        symbol: "square.grid.2x2",
        title: NSLocalizedString("library.empty", comment: ""),
        message: nil,
        actions: [])

    private lazy var errorStateView = EmptyStateView(
        symbol: "wifi.exclamationmark",
        title: NSLocalizedString("library.error.title", comment: ""),
        message: nil,
        actions: [retryButton, openFolderButton])

    private let progressCard = ConsoleCard(
        cornerRadius: 12,
        inset: NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 10),
        fill: ConsoleTheme.Color.cardFillElevated)
    private let progressLabel = NSTextField(labelWithString: "")
    private let progressSpinner = NSProgressIndicator()
    private let cancelButton = NSButton(title: "", target: nil, action: nil)

    private var selectedCategory = "all"
    private var categorySignature = ""
    private var rowsSignature = ""
    private var didActivate = false

    init(service: TemplateLibraryService) {
        self.service = service
        super.init(frame: .zero)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func activate() {
        didActivate = true
        refresh()
        Task { @MainActor in
            await service.ensureLoaded()
            self.refresh()
        }
    }

    func refresh() {
        refreshButton.isEnabled = !service.isRefreshing && !service.isInstalling
        if service.isRefreshing {
            refreshButton.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath",
                                          accessibilityDescription: nil)
        } else {
            refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise",
                                          accessibilityDescription: nil)
        }

        updateUpdatedLabel()
        updateBanner()
        rebuildCategoryPopupIfNeeded()
        rebuildRowsIfNeeded()
        updateStateViews()
        updateProgressCard()
    }

    // MARK: - 装配

    private func build() {
        searchField.placeholderString = NSLocalizedString("library.search", comment: "")
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.font = .systemFont(ofSize: 12)
        searchField.widthAnchor.constraint(equalToConstant: 220).isActive = true

        categoryPopup.target = self
        categoryPopup.action = #selector(categoryChanged)
        categoryPopup.controlSize = .regular
        categoryPopup.font = .systemFont(ofSize: 11.5)
        categoryPopup.widthAnchor.constraint(equalToConstant: 120).isActive = true

        updatedLabel.font = ConsoleTheme.Font.micro
        updatedLabel.textColor = .tertiaryLabelColor
        updatedLabel.alignment = .right
        updatedLabel.lineBreakMode = .byTruncatingTail
        updatedLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let controls = NSStackView(views: [searchField, categoryPopup, updatedLabel])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = ConsoleTheme.Space.xs

        noticeView.translatesAutoresizingMaskIntoConstraints = false
        noticeContainer.addSubview(noticeView)
        NSLayoutConstraint.activate([
            noticeView.leadingAnchor.constraint(equalTo: noticeContainer.leadingAnchor),
            noticeView.trailingAnchor.constraint(equalTo: noticeContainer.trailingAnchor),
            noticeView.topAnchor.constraint(equalTo: noticeContainer.topAnchor),
            noticeView.bottomAnchor.constraint(equalTo: noticeContainer.bottomAnchor),
        ])
        let height = noticeContainer.heightAnchor.constraint(equalToConstant: 0)
        height.isActive = true
        noticeHeightConstraint = height
        noticeView.isHidden = true

        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 46, right: 0)
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        rowsStack.orientation = .vertical
        // 纵向 stack 的 .width 对齐无效（会被忽略，卡片按内容宽度缩着排），
        // 卡片宽度由 rebuildRowsIfNeeded 里显式约束到列表宽度。
        rowsStack.alignment = .leading
        rowsStack.spacing = ConsoleTheme.Space.xs
        rowsStack.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 18, right: 0)
        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = rowsStack
        NSLayoutConstraint.activate([
            rowsStack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            rowsStack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            rowsStack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            rowsStack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])

        loadingIndicator.style = .spinning
        loadingIndicator.controlSize = .small
        loadingIndicator.isDisplayedWhenStopped = false
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false

        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.isHidden = true
        errorStateView.translatesAutoresizingMaskIntoConstraints = false
        errorStateView.isHidden = true

        progressLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        progressSpinner.style = .spinning
        progressSpinner.controlSize = .small
        progressSpinner.isDisplayedWhenStopped = false
        cancelButton.title = NSLocalizedString("library.cancel", comment: "")
        cancelButton.target = self
        cancelButton.action = #selector(cancelInstall)
        cancelButton.bezelStyle = .rounded
        cancelButton.controlSize = .small
        cancelButton.font = .systemFont(ofSize: 11)
        cancelButton.setContentHuggingPriority(.required, for: .horizontal)

        let progressStack = NSStackView(views: [progressSpinner, progressLabel, cancelButton])
        progressStack.orientation = .horizontal
        progressStack.alignment = .centerY
        progressStack.spacing = 8
        progressStack.translatesAutoresizingMaskIntoConstraints = false
        progressCard.contentView.addSubview(progressStack)
        NSLayoutConstraint.activate([
            progressStack.leadingAnchor.constraint(equalTo: progressCard.contentView.leadingAnchor),
            progressStack.trailingAnchor.constraint(equalTo: progressCard.contentView.trailingAnchor),
            progressStack.topAnchor.constraint(equalTo: progressCard.contentView.topAnchor),
            progressStack.bottomAnchor.constraint(equalTo: progressCard.contentView.bottomAnchor),
        ])
        progressCard.isHidden = true
        progressCard.translatesAutoresizingMaskIntoConstraints = false

        header.translatesAutoresizingMaskIntoConstraints = false
        controls.translatesAutoresizingMaskIntoConstraints = false
        noticeContainer.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        errorStateView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(header)
        addSubview(controls)
        addSubview(noticeContainer)
        addSubview(scrollView)
        addSubview(loadingIndicator)
        addSubview(emptyStateView)
        addSubview(errorStateView)
        addSubview(progressCard)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor,
                                            constant: ConsoleTheme.Space.pageInset),
            header.trailingAnchor.constraint(equalTo: trailingAnchor,
                                             constant: -ConsoleTheme.Space.pageInset),

            controls.topAnchor.constraint(equalTo: header.bottomAnchor,
                                          constant: ConsoleTheme.Space.md),
            controls.leadingAnchor.constraint(equalTo: leadingAnchor,
                                              constant: ConsoleTheme.Space.pageInset),
            controls.trailingAnchor.constraint(equalTo: trailingAnchor,
                                               constant: -ConsoleTheme.Space.pageInset),

            noticeContainer.topAnchor.constraint(equalTo: controls.bottomAnchor,
                                                 constant: ConsoleTheme.Space.sm),
            noticeContainer.leadingAnchor.constraint(equalTo: leadingAnchor,
                                                     constant: ConsoleTheme.Space.pageInset),
            noticeContainer.trailingAnchor.constraint(equalTo: trailingAnchor,
                                                      constant: -ConsoleTheme.Space.pageInset),

            scrollView.topAnchor.constraint(equalTo: noticeContainer.bottomAnchor,
                                            constant: ConsoleTheme.Space.sm),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor,
                                                constant: ConsoleTheme.Space.pageInset),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor,
                                                 constant: -ConsoleTheme.Space.pageInset),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor,
                                               constant: -ConsoleTheme.Space.sm),

            loadingIndicator.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),

            emptyStateView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            emptyStateView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            emptyStateView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),

            errorStateView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            errorStateView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            errorStateView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            errorStateView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),

            progressCard.leadingAnchor.constraint(equalTo: leadingAnchor,
                                                  constant: ConsoleTheme.Space.pageInset),
            progressCard.trailingAnchor.constraint(equalTo: trailingAnchor,
                                                   constant: -ConsoleTheme.Space.pageInset),
            progressCard.bottomAnchor.constraint(equalTo: bottomAnchor,
                                                 constant: -ConsoleTheme.Space.sm),
        ])
    }

    // MARK: - 更新

    private func updateUpdatedLabel() {
        guard let snapshot = service.snapshot else {
            updatedLabel.stringValue = NSLocalizedString("library.updated.none", comment: "")
            return
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let date = formatter.string(from: snapshot.fetchedAt)
        let format = NSLocalizedString(
            snapshot.isReadOnly ? "library.updated.cached" : "library.updated", comment: "")
        updatedLabel.stringValue = String(format: format, date)
    }

    private func updateBanner() {
        let text: String?
        if service.stateReadOnly {
            text = NSLocalizedString("library.banner.readOnly", comment: "")
        } else if service.snapshot?.isReadOnly == true {
            text = NSLocalizedString("library.banner.offline", comment: "")
        } else {
            text = nil
        }

        if let text {
            noticeView.configure(text: text)
            noticeView.isHidden = false
            noticeHeightConstraint?.isActive = false
        } else {
            noticeView.isHidden = true
            noticeHeightConstraint?.isActive = true
        }
    }

    private func rebuildCategoryPopupIfNeeded() {
        let categories = service.snapshot?.index.categoryList ?? []
        let signature = categories.map(\.id).joined(separator: "|")
        guard signature != categorySignature else { return }
        categorySignature = signature
        let selected = selectedCategory
        categoryPopup.removeAllItems()
        categoryPopup.addItem(withTitle: NSLocalizedString("library.filter.all", comment: ""))
        categoryPopup.lastItem?.representedObject = "all"
        for category in categories {
            categoryPopup.addItem(withTitle: category.name(
                preferredLanguages: LanguageTag.templatePreferredLanguages))
            categoryPopup.lastItem?.representedObject = category.id
        }
        if let item = categoryPopup.itemArray.first(where: {
            ($0.representedObject as? String) == selected
        }) {
            categoryPopup.select(item)
        } else {
            selectedCategory = "all"
            categoryPopup.selectItem(at: 0)
        }
    }

    private func filteredRows() -> [TemplateLibraryService.Row] {
        let query = searchField.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return service.rows.filter { row in
            let categoryMatch = selectedCategory == "all"
                || row.entry.category == selectedCategory
            guard categoryMatch else { return false }
            guard !query.isEmpty else { return true }
            return row.localizedName.lowercased().contains(query)
                || row.localizedDescription.lowercased().contains(query)
                || row.entry.id.contains(query)
                || (row.entry.author?.name.lowercased().contains(query) ?? false)
                || (row.entry.tags ?? []).contains(where: { $0.contains(query) })
        }
    }

    private func rebuildRowsIfNeeded() {
        let filtered = filteredRows()
        let signature = filtered.map { row in
            [row.entry.id,
             row.entry.version,
             row.evaluation.installState.rawValue,
             row.evaluation.updateAvailable ? "1" : "0",
             row.evaluation.isEdited ? "1" : "0",
             row.evaluation.isIgnored ? "1" : "0",
             row.evaluation.needsNewerApp ? "1" : "0",
             row.record?.sha256 ?? ""].joined(separator: ":")
        }.joined(separator: "|") + "|installing:\(service.isInstalling)"
        guard signature != rowsSignature else { return }
        rowsSignature = signature

        let origin = scrollView.contentView.bounds.origin
        for view in rowsStack.arrangedSubviews {
            rowsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for row in filtered {
            let card = TemplateLibraryCardView(service: service, row: row)
            card.onOpenInstalled = { [weak self] in
                self?.onOpenInstalled?(row.entry.file)
            }
            rowsStack.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
        }
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func updateStateViews() {
        let hasRows = !service.rows.isEmpty
        let isLoading = service.loadState == .loading && !hasRows
        let isFailed: String?
        if case .failed(let message) = service.loadState, !hasRows {
            isFailed = message
        } else {
            isFailed = nil
        }

        if isLoading {
            loadingIndicator.startAnimation(nil)
        } else {
            loadingIndicator.stopAnimation(nil)
        }
        loadingIndicator.isHidden = !isLoading
        scrollView.isHidden = isLoading || isFailed != nil
        errorStateView.isHidden = true
        emptyStateView.isHidden = true

        if let isFailed {
            errorStateView.configure(
                title: NSLocalizedString("library.error.title", comment: ""),
                message: isFailed)
            errorStateView.isHidden = false
        } else if !isLoading {
            let filtered = filteredRows()
            if hasRows, filtered.isEmpty {
                emptyStateView.configure(
                    title: NSLocalizedString("library.empty.filtered", comment: ""),
                    message: nil)
                emptyStateView.isHidden = false
            } else if !hasRows, service.loadState == .loaded {
                emptyStateView.configure(
                    title: NSLocalizedString("library.empty", comment: ""),
                    message: nil)
                emptyStateView.isHidden = false
            }
        }
    }

    private func updateProgressCard() {
        guard let progress = service.progress else {
            progressCard.isHidden = true
            return
        }
        progressCard.isHidden = false
        let phase: String
        switch progress.phase {
        case .downloading:
            phase = NSLocalizedString("library.phase.downloading", comment: "")
        case .verifying:
            phase = NSLocalizedString("library.phase.verifying", comment: "")
        case .installing:
            phase = NSLocalizedString("library.phase.installing", comment: "")
        case .done:
            phase = NSLocalizedString("library.phase.done", comment: "")
        }
        let name = service.rows.first(where: { $0.entry.id == progress.templateID })?
            .localizedName ?? progress.templateID
        progressLabel.stringValue = "\(phase) · \(name)"
        cancelButton.isHidden = progress.phase == .done
        if progress.phase == .done {
            progressSpinner.stopAnimation(nil)
        } else {
            progressSpinner.startAnimation(nil)
        }
    }

    // MARK: - Actions

    @objc private func refreshTapped() {
        Task { @MainActor in
            await service.refresh(force: true)
            self.refresh()
        }
    }

    @objc private func categoryChanged() {
        selectedCategory = categoryPopup.selectedItem?.representedObject as? String ?? "all"
        rowsSignature = ""
        rebuildRowsIfNeeded()
        updateStateViews()
    }

    func controlTextDidChange(_ obj: Notification) {
        rebuildRowsIfNeeded()
        updateStateViews()
    }

    @objc private func cancelInstall() {
        service.cancelInstall()
    }

    @objc private func openTemplatesFolder() {
        NSWorkspace.shared.open(TemplateStore.userTemplatesDirectory())
    }
}
