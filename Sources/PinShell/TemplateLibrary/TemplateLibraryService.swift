import AppKit
import Foundation
import PinShellCore

extension Notification.Name {
    static let pinshellTemplateInstalled = Notification.Name("PinShell.templateInstalled")
}

@MainActor
final class TemplateLibraryService {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    enum InstallPhase: Equatable {
        case downloading
        case verifying
        case installing
        case done
    }

    struct Progress: Equatable {
        let templateID: String
        var phase: InstallPhase
    }

    enum ConflictDecision {
        case cancel
        case backupAndInstall
        case replace
    }

    struct Row: Equatable {
        let entry: TemplateLibraryEntry
        let evaluation: TemplateLibraryEvaluation
        let record: InstalledTemplateRecord?
        let source: TemplateLibrarySource
        /// 该来源当前是否只能读缓存；缓存来源的模板不可安装。
        let sourceIsReadOnly: Bool

        var isOfficialSource: Bool { source.isOfficial }
        var sourceDisplayName: String { source.displayName }

        var localizedName: String {
            entry.localizedName(preferredLanguages: LanguageTag.templatePreferredLanguages)
        }

        var localizedDescription: String {
            entry.localizedDescription(preferredLanguages: LanguageTag.templatePreferredLanguages)
        }

        var localizedListing: TemplateLibraryListing? {
            entry.listing(preferredLanguages: LanguageTag.templatePreferredLanguages)
        }
    }

    /// 单个来源的加载状态，供通用页展示来源健康度。
    struct SourceStatus: Equatable {
        let source: TemplateLibrarySource
        var isLoaded = false
        var isReadOnly = false
        var templateCount = 0
        /// 因 id 已被更靠前的来源占用而跳过的模板。
        var skippedTemplateIDs: [String] = []
        var error: String?

        var skippedCount: Int { skippedTemplateIDs.count }
    }

    /// 添加来源前的检查结果：冲突项已能定位到占用该 id 的既有来源。
    struct SourceConflict: Equatable {
        let templateID: String
        let templateName: String
        let existingSourceName: String
    }

    struct SourcePreview: Equatable {
        let conflicts: [SourceConflict]
        /// 拉取失败时记录原因；此时无法检查冲突，但仍允许添加。
        let fetchError: String?
    }

    enum ServiceError: LocalizedError {
        case catalogUnavailable
        case busy
        case requiresNewerApp(String)
        case invalidUTF8
        case localChanged
        case stateReadOnly
        case backupFailed
        case payloadInvalid(String)
        case templateNotFound(String)

        var errorDescription: String? {
            switch self {
            case .catalogUnavailable:
                return NSLocalizedString("library.error.catalogUnavailable", comment: "")
            case .busy:
                return NSLocalizedString("library.error.busy", comment: "")
            case .requiresNewerApp(let version):
                return String(
                    format: NSLocalizedString("library.error.requiresNewerApp", comment: ""),
                    version)
            case .invalidUTF8:
                return NSLocalizedString("library.error.invalidUTF8", comment: "")
            case .localChanged:
                return NSLocalizedString("library.error.localChanged", comment: "")
            case .stateReadOnly:
                return NSLocalizedString("library.error.stateReadOnly", comment: "")
            case .backupFailed:
                return NSLocalizedString("library.error.backupFailed", comment: "")
            case .payloadInvalid(let message):
                return String(
                    format: NSLocalizedString("library.error.payload", comment: ""),
                    message)
            case .templateNotFound(let id):
                return String(
                    format: NSLocalizedString("library.error.templateNotFound", comment: ""),
                    id)
            }
        }
    }

    private(set) var sources: [TemplateLibrarySource] = []
    private(set) var snapshots: [String: TemplateCatalogSnapshot] = [:]
    private(set) var sourceStatuses: [SourceStatus] = []
    private(set) var categories: [TemplateLibraryCategory] = []
    private(set) var state: TemplateLibraryState
    private(set) var rows: [Row] = []
    private(set) var loadState: LoadState = .idle
    private(set) var isRefreshing = false
    private(set) var progress: Progress?
    private(set) var stateWarning: String?
    private(set) var stateReadOnly = false

    var onChange: (() -> Void)?
    var onError: ((String) -> Void)?

    private let client: TemplateCatalogClient
    private let stateStore: TemplateLibraryStateStore
    private let templatesDirectory: URL
    private let appDirectory: URL
    private weak var windowController: OverlayWindowController?
    private var installTask: Task<Result<Void, Error>, Never>?
    /// 串行刷新循环：请求排队，调用方在覆盖它的那一轮完成后返回。
    private var refreshTask: Task<Void, Never>?
    private struct RefreshRequest {
        let force: Bool
        let continuation: CheckedContinuation<Void, Never>?
    }
    private var pendingRefreshes: [RefreshRequest] = []
    /// 刷新途中新增来源：本轮结束后再跑一轮。
    private var needsRefreshAgain = false
    private var sourceErrors: [String: String] = [:]
    private var didPrepare = false
    private var observer: NSObjectProtocol?

    private enum FetchResult: Sendable {
        case success(TemplateCatalogSnapshot)
        case failure(String)
    }

    init(windowController: OverlayWindowController?) {
        self.windowController = windowController
        self.sources = TemplateLibrarySource.configured()
        let appDirectory = ControlEndpoint.applicationDirectory()
        self.appDirectory = appDirectory
        self.templatesDirectory = appDirectory.appendingPathComponent("templates", isDirectory: true)
        self.stateStore = TemplateLibraryStateStore(
            url: appDirectory.appendingPathComponent("template-library.json"))
        self.client = TemplateCatalogClient(
            cacheDirectory: appDirectory.appendingPathComponent("CatalogCache", isDirectory: true))

        do {
            self.state = try stateStore.load()
        } catch let error as TemplateLibraryStateError {
            self.state = .empty
            self.stateReadOnly = true
            self.stateWarning = error.description
        } catch {
            self.state = .empty
            self.stateWarning = error.localizedDescription
        }

        rebuildRows()

        observer = NotificationCenter.default.addObserver(
            forName: .pinshellTemplatesChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.snapshots.isEmpty else { return }
                self.rebuildRows()
                self.onChange?()
            }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    var isCatalogReadOnly: Bool {
        snapshots.values.contains { $0.isReadOnly }
    }

    /// 所有已加载来源都只能读缓存。
    var isEntirelyOffline: Bool {
        !snapshots.isEmpty && snapshots.values.allSatisfy(\.isReadOnly)
    }

    var latestFetchedAt: Date? {
        snapshots.values.map(\.fetchedAt).max()
    }

    var updateCount: Int {
        rows.filter {
            $0.evaluation.updateAvailable && $0.evaluation.installState == .installed
        }.count
    }

    var isInstalling: Bool {
        installTask != nil
    }

    func prepareIfNeeded() {
        guard !didPrepare else { return }
        didPrepare = true
        guard !stateReadOnly else { return }
        let officialURL = sources.first(where: \.isOfficial)?.url
            ?? TemplateLibraryPreferences.catalogURL()
        let migrated = LegacyTemplateMigrator.migrate(
            state: state,
            templatesDirectory: templatesDirectory,
            sourceCatalog: officialURL)
        if migrated != state {
            state = migrated
            try? stateStore.save(state)
        }
    }

    func ensureLoaded() async {
        prepareIfNeeded()
        switch loadState {
        case .idle, .failed:
            await refresh()
        case .loading, .loaded:
            if let refreshTask {
                await refreshTask.value
            } else {
                rebuildRows()
                onChange?()
            }
        }
    }

    /// 加载所有来源。请求由单一循环串行处理：每个调用都在覆盖它的那一轮完成后返回，
    /// `force` 请求保证至少有一轮强制拉取，避免拿着旧快照继续判断。
    func refresh(force: Bool = false) async {
        await withCheckedContinuation { continuation in
            pendingRefreshes.append(RefreshRequest(force: force, continuation: continuation))
            startRefreshLoopIfNeeded()
        }
    }

    private func startRefreshLoopIfNeeded() {
        guard refreshTask == nil else { return }
        isRefreshing = true
        if loadState == .idle {
            loadState = .loading
        }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            while !self.pendingRefreshes.isEmpty {
                let batch = self.pendingRefreshes
                self.pendingRefreshes.removeAll()
                await self.performRefresh(force: batch.contains { $0.force })
                batch.compactMap(\.continuation).forEach { $0.resume() }
                if self.needsRefreshAgain {
                    self.needsRefreshAgain = false
                    self.pendingRefreshes.append(
                        RefreshRequest(force: true, continuation: nil))
                }
            }
            self.refreshTask = nil
            if self.pendingRefreshes.isEmpty {
                self.isRefreshing = false
                self.onChange?()
            } else {
                self.startRefreshLoopIfNeeded()
            }
        }
        onChange?()
    }

    private func performRefresh(force: Bool) async {
        prepareIfNeeded()
        let client = self.client
        let sources = self.sources
        var results: [String: FetchResult] = [:]
        await withTaskGroup(of: (String, FetchResult).self) { group in
            for source in sources {
                group.addTask {
                    do {
                        let snapshot = try await client.fetch(catalogURL: source.url,
                                                              forceRefresh: force)
                        return (source.id, .success(snapshot))
                    } catch {
                        return (source.id, .failure(error.localizedDescription))
                    }
                }
            }
            for await (id, result) in group {
                results[id] = result
            }
        }

        var firstError: String?
        for source in sources {
            guard let result = results[source.id] else { continue }
            switch result {
            case .success(let snapshot):
                snapshots[source.id] = snapshot
                sourceErrors[source.id] = nil
            case .failure(let message):
                sourceErrors[source.id] = message
                if firstError == nil { firstError = message }
            }
        }
        // 刷新途中来源可能被移除：丢弃已不在配置中的结果。
        let validIDs = Set(self.sources.map(\.id))
        snapshots = snapshots.filter { validIDs.contains($0.key) }
        sourceErrors = sourceErrors.filter { validIDs.contains($0.key) }
        // 刷新途中新增了来源：再跑一轮把它拉下来。
        let refreshedIDs = Set(sources.map(\.id))
        if self.sources.contains(where: { !refreshedIDs.contains($0.id) }) {
            needsRefreshAgain = true
        }

        reconcileState()
        rebuildRows()
        if snapshots.isEmpty, let firstError {
            loadState = .failed(firstError)
            onError?(firstError)
        } else {
            loadState = .loaded
        }
    }

    /// 外部编辑器/Finder 改动模板目录后，重新计算本地 hash 与状态。
    func revalidateLocalFiles() {
        guard !snapshots.isEmpty else { return }
        rebuildRows()
        onChange?()
    }

    // MARK: - 来源管理

    /// 添加前的只读检查：规范化地址，拉取候选目录，并与现有来源比较 id。
    /// 不写入偏好、不修改当前快照；校验失败会抛出 `AddCatalogError`。
    func previewSource(_ raw: String) async throws -> SourcePreview {
        let url = try TemplateLibraryPreferences.validateCustomCatalogURL(raw)
        // 两个请求互不依赖：已配置来源的加载与新目录的拉取并行进行。
        async let loaded: Void = ensureLoaded()
        async let candidate = client.fetch(catalogURL: url, forceRefresh: true)
        await loaded

        // rows 已按「官方优先、首个来源胜出」合并，可直接作为 id 占用者。
        var providers: [String: String] = [:]
        for row in rows where providers[row.entry.id] == nil {
            providers[row.entry.id] = row.source.localizedTitle
        }

        do {
            let snapshot = try await candidate
            let conflicts = snapshot.index.templates.compactMap { entry -> SourceConflict? in
                guard let provider = providers[entry.id] else { return nil }
                return SourceConflict(
                    templateID: entry.id,
                    templateName: entry.localizedName(
                        preferredLanguages: LanguageTag.templatePreferredLanguages),
                    existingSourceName: provider)
            }.sorted {
                $0.templateID.localizedStandardCompare($1.templateID) == .orderedAscending
            }
            return SourcePreview(conflicts: conflicts, fetchError: nil)
        } catch {
            return SourcePreview(conflicts: [], fetchError: error.localizedDescription)
        }
    }

    /// 添加附加来源并持久化；返回添加后的来源。拉取由调用方触发。
    @discardableResult
    func addSource(_ raw: String) throws -> TemplateLibrarySource {
        let url = try TemplateLibraryPreferences.addCustomCatalogURL(raw)
        reloadConfiguredSources()
        return sources.first(where: { $0.url.absoluteString == url.absoluteString })
            ?? TemplateLibrarySource(url: url, isOfficial: false)
    }

    func removeSource(_ source: TemplateLibrarySource) {
        guard !source.isOfficial else { return }
        TemplateLibraryPreferences.removeCustomCatalogURL(source.url)
        reloadConfiguredSources()
    }

    private func reloadConfiguredSources() {
        sources = TemplateLibrarySource.configured()
        let validIDs = Set(sources.map(\.id))
        snapshots = snapshots.filter { validIDs.contains($0.key) }
        sourceErrors = sourceErrors.filter { validIDs.contains($0.key) }
        rebuildRows()
        onChange?()
    }

    // MARK: - 查询

    func categoryName(for id: String?) -> String {
        guard let id,
              let category = categories.first(where: { $0.id == id }) else {
            return id ?? ""
        }
        return category.name(preferredLanguages: LanguageTag.templatePreferredLanguages)
    }

    /// 按 id 查询目录行；可选来源过滤用于深链定位到声明该模板的库。
    func row(id: String, catalogURL: URL? = nil) -> Row? {
        let target = catalogURL?.absoluteString
        return rows.first { row in
            row.entry.id == id
                && (target == nil || row.source.url.absoluteString == target)
        }
    }

    /// 官网深链入口：按 id 安装目录中的最新版本。
    /// 已是最新则直接返回；本地有修改时先备份再安装，不静默覆盖用户改动。
    func installTemplate(id: String, catalogURL: URL) async throws {
        await ensureLoaded()
        if row(id: id, catalogURL: catalogURL) == nil, !snapshots.isEmpty {
            await refresh(force: true)
        }
        guard !snapshots.isEmpty else {
            throw ServiceError.catalogUnavailable
        }
        guard let row = row(id: id, catalogURL: catalogURL) else {
            throw ServiceError.templateNotFound(id)
        }
        if row.evaluation.installState == .installed && !row.evaluation.updateAvailable {
            return
        }
        let conflict: ConflictDecision = conflictDecisionNeeded(for: row)
            ? .backupAndInstall
            : .replace
        try await install(row, conflict: conflict)
    }

    func conflictDecisionNeeded(for row: Row) -> Bool {
        let url = localURL(for: row.entry)
        guard fileExists(url) else { return false }
        guard let record = row.record else { return true }
        let hash = try? FileDigest.sha256(of: url)
        return hash != record.sha256
    }

    func install(_ row: Row, conflict: ConflictDecision) async throws {
        guard let snapshot = snapshots[row.source.id], !snapshot.isReadOnly else {
            throw ServiceError.catalogUnavailable
        }
        guard installTask == nil else { throw ServiceError.busy }
        guard !stateReadOnly else { throw ServiceError.stateReadOnly }
        guard !row.evaluation.needsNewerApp else {
            throw ServiceError.requiresNewerApp(row.entry.minimumAppVersion)
        }
        guard conflict != .cancel else { return }

        let entry = row.entry
        let localURL = localURL(for: entry)
        let hadLocalFile = fileExists(localURL)
        let beforeHash = hadLocalFile ? try? FileDigest.sha256(of: localURL) : nil
        let backup = hadLocalFile && conflict == .backupAndInstall
        progress = Progress(templateID: entry.id, phase: .downloading)
        onChange?()

        let catalogURL = row.source.url
        let task = Task { () -> Result<Void, Error> in
            do {
                try await self.performInstall(
                    entry: entry,
                    catalogURL: catalogURL,
                    localURL: localURL,
                    beforeHash: beforeHash,
                    backup: backup)
                return .success(())
            } catch {
                return .failure(error)
            }
        }
        installTask = task
        let result = await task.value
        installTask = nil

        switch result {
        case .success:
            progress = Progress(templateID: entry.id, phase: .done)
            onChange?()
            try? await Task.sleep(nanoseconds: 900_000_000)
            if progress?.templateID == entry.id {
                progress = nil
                onChange?()
            }
        case .failure(let error):
            progress = nil
            onChange?()
            if error is CancellationError { return }
            throw error
        }
    }

    func cancelInstall() {
        installTask?.cancel()
    }

    func ignore(_ row: Row) throws {
        guard !stateReadOnly else { throw ServiceError.stateReadOnly }
        state.ignored[row.entry.id] = row.entry.version
        try stateStore.save(state)
        rebuildRows()
        onChange?()
    }

    func unignore(_ row: Row) throws {
        guard !stateReadOnly else { throw ServiceError.stateReadOnly }
        state.ignored.removeValue(forKey: row.entry.id)
        try stateStore.save(state)
        rebuildRows()
        onChange?()
    }

    func openWebsite(for row: Row) {
        guard let page = row.entry.pageURLString(
            preferredLanguages: LanguageTag.templatePreferredLanguages),
              let url = URL(string: page, relativeTo: row.source.url)?.absoluteURL else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func revealInFinder(_ row: Row) {
        let url = localURL(for: row.entry)
        if fileExists(url) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(templatesDirectory)
        }
    }

    func installedVersion(forFile file: String) -> String? {
        if let row = rows.first(where: { $0.entry.file == file }) {
            return state.installed[row.entry.id]?.version
        }
        // 目录尚未加载时也能按文件名反推 id。
        let id = (file as NSString).deletingPathExtension
        return state.installed[id]?.version
    }

    func isEdited(file: String) -> Bool {
        rows.first(where: { $0.entry.file == file })?.evaluation.isEdited ?? false
    }

    /// 已安装模板对应的目录作者信息；目录未加载或文件不是从模板库安装时返回 nil。
    func author(forFile file: String) -> TemplateLibraryAuthor? {
        guard let row = rows.first(where: { $0.entry.file == file }),
              state.installed[row.entry.id] != nil else { return nil }
        return row.entry.author
    }

    // MARK: - Private

    private func performInstall(entry: TemplateLibraryEntry,
                                catalogURL: URL,
                                localURL: URL,
                                beforeHash: String?,
                                backup: Bool) async throws {
        try Task.checkCancellation()
        let data = try await client.downloadPayload(entry.payload.url,
                                                   relativeTo: catalogURL)
        try Task.checkCancellation()

        progress?.phase = .verifying
        onChange?()
        do {
            try TemplatePayloadVerifier.verify(
                data: data,
                expectedBytes: entry.payload.bytes,
                expectedSHA256: entry.payload.sha256)
        } catch {
            throw ServiceError.payloadInvalid(error.localizedDescription)
        }
        guard String(data: data, encoding: .utf8) != nil else {
            throw ServiceError.invalidUTF8
        }

        let currentHash = fileExists(localURL)
            ? try? FileDigest.sha256(of: localURL)
            : nil
        guard currentHash == beforeHash else { throw ServiceError.localChanged }

        if backup, fileExists(localURL) {
            try backupTemplate(entry.id, at: localURL)
        }
        try Task.checkCancellation()

        progress?.phase = .installing
        onChange?()
        let written = try TemplateStorage.write(name: entry.file,
                                                data: data,
                                                in: templatesDirectory)
        state.installed[entry.id] = InstalledTemplateRecord(
            version: entry.version,
            sha256: entry.payload.sha256,
            installedAt: Date(),
            sourceCatalog: catalogURL.absoluteString)
        state.ignored.removeValue(forKey: entry.id)
        try stateStore.save(state)

        rebuildRows()
        NotificationCenter.default.post(name: .pinshellTemplatesChanged,
                                        object: written)
        NotificationCenter.default.post(name: .pinshellTemplateInstalled,
                                        object: written)
        if windowController?.currentURL?.standardizedFileURL == written.standardizedFileURL {
            windowController?.reloadHTML()
        }
        onChange?()
    }

    private func reconcileState() {
        guard !stateReadOnly, !snapshots.isEmpty else { return }
        var changed = false
        var seenIDs = Set<String>()
        for source in sources {
            guard let snapshot = snapshots[source.id] else { continue }
            for entry in snapshot.index.templates {
                guard seenIDs.insert(entry.id).inserted else { continue }
                let url = localURL(for: entry)
                if state.installed[entry.id] != nil {
                    if !fileExists(url) {
                        state.installed[entry.id] = nil
                        changed = true
                    }
                } else if fileExists(url),
                          let hash = try? FileDigest.sha256(of: url),
                          hash == entry.payload.sha256 {
                    state.installed[entry.id] = InstalledTemplateRecord(
                        version: entry.version,
                        sha256: hash,
                        installedAt: Date(),
                        sourceCatalog: source.url.absoluteString)
                    changed = true
                }
            }
        }
        if changed {
            try? stateStore.save(state)
        }
    }

    /// 合并所有来源：官方库优先，同 id 的模板只保留第一个来源。
    private func rebuildRows() {
        let appVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        var seenIDs = Set<String>()
        var seenCategories = Set<String>()
        var newRows: [Row] = []
        var newCategories: [TemplateLibraryCategory] = []
        var statuses: [SourceStatus] = []

        for source in sources {
            var status = SourceStatus(source: source)
            if let snapshot = snapshots[source.id] {
                status.isLoaded = true
                status.isReadOnly = snapshot.isReadOnly
                for category in snapshot.index.categoryList
                    where seenCategories.insert(category.id).inserted {
                    newCategories.append(category)
                }
                for entry in snapshot.index.templates.sortedForLibrary() {
                    guard seenIDs.insert(entry.id).inserted else {
                        status.skippedTemplateIDs.append(entry.id)
                        continue
                    }
                    let url = localURL(for: entry)
                    let localHash = fileExists(url) ? try? FileDigest.sha256(of: url) : nil
                    let record = state.installed[entry.id]
                    let evaluation = TemplateLibraryEvaluator.evaluate(
                        entry: entry,
                        record: record,
                        localSHA256: localHash,
                        appVersion: appVersion,
                        ignoredVersion: state.ignored[entry.id])
                    newRows.append(Row(
                        entry: entry,
                        evaluation: evaluation,
                        record: record,
                        source: source,
                        sourceIsReadOnly: snapshot.isReadOnly))
                    status.templateCount += 1
                }
            }
            status.error = sourceErrors[source.id]
            statuses.append(status)
        }

        rows = newRows
        categories = newCategories
        sourceStatuses = statuses
    }

    private func localURL(for entry: TemplateLibraryEntry) -> URL {
        templatesDirectory.appendingPathComponent(entry.file)
    }

    private func fileExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }

    private func backupTemplate(_ id: String, at url: URL) throws {
        let fm = FileManager.default
        let directory = appDirectory.appendingPathComponent(
            "Backups/Templates", isDirectory: true)
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent("\(id)-\(timestamp()).html")
            try fm.copyItem(at: url, to: destination)
            pruneBackups(directory: directory, prefix: "\(id)-")
        } catch {
            throw ServiceError.backupFailed
        }
    }

    private func pruneBackups(directory: URL, prefix: String) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let matching = files
            .filter { $0.lastPathComponent.hasPrefix(prefix) }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                return l > r
            }
        for url in matching.dropFirst(5) {
            try? fm.removeItem(at: url)
        }
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.string(from: Date())
    }
}
