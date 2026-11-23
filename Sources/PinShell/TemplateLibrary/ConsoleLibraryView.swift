import AppKit
import PinShellCore

/// Console 的“在线模板库”页：catalog 列表、搜索/分类、安装/更新/忽略。
@MainActor
final class ConsoleLibraryView: NSView, NSSearchFieldDelegate {
    private let service: TemplateLibraryService

    var onOpenInstalled: ((String) -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(wrappingLabelWithString: "")
    private let updatedLabel = NSTextField(labelWithString: "")
    private let refreshButton = NSButton(title: "", target: nil, action: nil)
    private let bannerLabel = NSTextField(wrappingLabelWithString: "")
    private let searchField = NSSearchField()
    private let categoryPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let scrollView = NSScrollView()
    private let rowsStack = FlippedStackView()
    private let loadingIndicator = NSProgressIndicator()
    private let emptyLabel = NSTextField(wrappingLabelWithString: "")
    private let errorView = NSStackView()
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let progressCard = NSView()
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
        titleLabel.stringValue = NSLocalizedString("library.title", comment: "")
        subtitleLabel.stringValue = NSLocalizedString("library.subtitle", comment: "")
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
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail

        subtitleLabel.font = .systemFont(ofSize: 11.5)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.maximumNumberOfLines = 2

        let titleStack = NSStackView(views: [titleLabel, subtitleLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 3

        refreshButton.target = self
        refreshButton.action = #selector(refreshTapped)
        refreshButton.bezelStyle = .rounded
        refreshButton.controlSize = .regular
        refreshButton.imagePosition = .imageLeading
        refreshButton.title = NSLocalizedString("library.refresh", comment: "")
        refreshButton.font = .systemFont(ofSize: 11.5, weight: .medium)
        refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise",
                                      accessibilityDescription: nil)
        refreshButton.setContentHuggingPriority(.required, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let header = NSStackView(views: [titleStack, spacer, refreshButton])
        header.orientation = .horizontal
        header.alignment = .top
        header.spacing = 12

        searchField.placeholderString = NSLocalizedString("library.search", comment: "")
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.font = .systemFont(ofSize: 11.5)
        searchField.widthAnchor.constraint(equalToConstant: 220).isActive = true

        categoryPopup.target = self
        categoryPopup.action = #selector(categoryChanged)
        categoryPopup.controlSize = .regular
        categoryPopup.font = .systemFont(ofSize: 11.5)
        categoryPopup.widthAnchor.constraint(equalToConstant: 120).isActive = true

        updatedLabel.font = .systemFont(ofSize: 10.5)
        updatedLabel.textColor = .tertiaryLabelColor
        updatedLabel.alignment = .right
        updatedLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let controls = NSStackView(views: [searchField, categoryPopup, updatedLabel])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 10

        bannerLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        bannerLabel.textColor = .systemOrange
        bannerLabel.maximumNumberOfLines = 2
        bannerLabel.isHidden = true

        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 46, right: 0)
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        rowsStack.orientation = .vertical
        rowsStack.alignment = .width
        rowsStack.spacing = 10
        rowsStack.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 18, right: 0)
        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = rowsStack
        NSLayoutConstraint.activate([
            rowsStack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            rowsStack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            rowsStack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            rowsStack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])

        emptyLabel.font = .systemFont(ofSize: 11.5)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true

        loadingIndicator.style = .spinning
        loadingIndicator.controlSize = .small
        loadingIndicator.isDisplayedWhenStopped = false
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false

        errorLabel.font = .systemFont(ofSize: 11.5)
        errorLabel.textColor = .secondaryLabelColor
        errorLabel.alignment = .center
        errorLabel.maximumNumberOfLines = 4
        errorLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 360).isActive = true

        let errorIcon = NSImageView(image: NSImage(
            systemSymbolName: "wifi.exclamationmark",
            accessibilityDescription: nil) ?? NSImage())
        errorIcon.contentTintColor = .tertiaryLabelColor
        errorIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 26, weight: .regular)

        let retryButton = NSButton(title: NSLocalizedString("library.retry", comment: ""),
                                   target: self, action: #selector(refreshTapped))
        retryButton.bezelStyle = .rounded
        retryButton.controlSize = .large
        retryButton.font = .systemFont(ofSize: 12, weight: .medium)

        let openFolderButton = NSButton(
            title: NSLocalizedString("console.empty.openFolder", comment: ""),
            target: self, action: #selector(openTemplatesFolder))
        openFolderButton.bezelStyle = .rounded
        openFolderButton.controlSize = .large
        openFolderButton.font = .systemFont(ofSize: 12, weight: .medium)

        errorView.orientation = .vertical
        errorView.alignment = .centerX
        errorView.spacing = 10
        errorView.setViews([errorIcon, errorLabel, retryButton, openFolderButton], in: .center)
        errorView.isHidden = true
        errorView.translatesAutoresizingMaskIntoConstraints = false

        progressCard.wantsLayer = true
        progressCard.layer?.cornerRadius = 12
        progressCard.layer?.cornerCurve = .continuous
        progressCard.layer?.backgroundColor = NSColor.controlBackgroundColor
            .withAlphaComponent(0.92).cgColor
        progressCard.layer?.borderWidth = 0.5
        progressCard.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        progressCard.isHidden = true
        progressCard.translatesAutoresizingMaskIntoConstraints = false

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
        progressStack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 10)
        progressStack.translatesAutoresizingMaskIntoConstraints = false
        progressCard.addSubview(progressStack)
        NSLayoutConstraint.activate([
            progressStack.leadingAnchor.constraint(equalTo: progressCard.leadingAnchor),
            progressStack.trailingAnchor.constraint(equalTo: progressCard.trailingAnchor),
            progressStack.topAnchor.constraint(equalTo: progressCard.topAnchor),
            progressStack.bottomAnchor.constraint(equalTo: progressCard.bottomAnchor),
        ])

        addSubview(header)
        addSubview(controls)
        addSubview(bannerLabel)
        addSubview(scrollView)
        addSubview(loadingIndicator)
        addSubview(emptyLabel)
        addSubview(errorView)
        addSubview(progressCard)

        header.translatesAutoresizingMaskIntoConstraints = false
        controls.translatesAutoresizingMaskIntoConstraints = false
        bannerLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),

            controls.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            controls.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            controls.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),

            bannerLabel.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 8),
            bannerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            bannerLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),

            scrollView.topAnchor.constraint(equalTo: bannerLabel.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),

            loadingIndicator.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor, constant: -20),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: scrollView.leadingAnchor, constant: 20),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: scrollView.trailingAnchor, constant: -20),

            errorView.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            errorView.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor, constant: -10),
            errorView.leadingAnchor.constraint(greaterThanOrEqualTo: scrollView.leadingAnchor, constant: 20),
            errorView.trailingAnchor.constraint(lessThanOrEqualTo: scrollView.trailingAnchor, constant: -20),

            progressCard.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            progressCard.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),
            progressCard.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
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
        if service.stateReadOnly {
            bannerLabel.stringValue = NSLocalizedString("library.banner.readOnly", comment: "")
            bannerLabel.isHidden = false
        } else if service.snapshot?.isReadOnly == true {
            bannerLabel.stringValue = NSLocalizedString("library.banner.offline", comment: "")
            bannerLabel.isHidden = false
        } else {
            bannerLabel.stringValue = ""
            bannerLabel.isHidden = true
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
        errorView.isHidden = isFailed == nil
        errorLabel.stringValue = isFailed ?? ""

        let filtered = filteredRows()
        if !isLoading, isFailed == nil, hasRows, filtered.isEmpty {
            emptyLabel.stringValue = NSLocalizedString("library.empty.filtered", comment: "")
            emptyLabel.isHidden = false
        } else if !isLoading, isFailed == nil, !hasRows,
                  service.loadState == .loaded {
            emptyLabel.stringValue = NSLocalizedString("library.empty", comment: "")
            emptyLabel.isHidden = false
        } else {
            emptyLabel.isHidden = true
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
