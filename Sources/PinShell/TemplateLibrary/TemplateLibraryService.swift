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

    private(set) var snapshot: TemplateCatalogSnapshot?
    private(set) var state: TemplateLibraryState
    private(set) var rows: [Row] = []
    private(set) var loadState: LoadState = .idle
    private(set) var isRefreshing = false
    private(set) var progress: Progress?
    private(set) var stateWarning: String?
    private(set) var stateReadOnly = false

    var onChange: (() -> Void)?
    var onError: ((String) -> Void)?

    let catalogURL: URL

    private let client: TemplateCatalogClient
    private let stateStore: TemplateLibraryStateStore
    private let templatesDirectory: URL
    private let appDirectory: URL
    private weak var windowController: OverlayWindowController?
    private var installTask: Task<Result<Void, Error>, Never>?
    /// 进行中的 catalog 请求；`ensureLoaded` / `installTemplate` 共享同一次加载。
    private var refreshTask: Task<Void, Never>?
    private var didPrepare = false
    private var observer: NSObjectProtocol?

    init(windowController: OverlayWindowController?) {
        self.windowController = windowController
        self.catalogURL = TemplateLibraryPreferences.catalogURL()
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

        observer = NotificationCenter.default.addObserver(
            forName: .pinshellTemplatesChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.snapshot != nil else { return }
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

    var isCatalogReadOnly: Bool { snapshot?.isReadOnly == true }

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
        let migrated = LegacyTemplateMigrator.migrate(
            state: state,
            templatesDirectory: templatesDirectory,
            sourceCatalog: catalogURL)
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
        case .loading:
            if let refreshTask { await refreshTask.value }
        case .loaded:
            if let refreshTask {
                await refreshTask.value
            } else {
                rebuildRows()
                onChange?()
            }
        }
    }

    /// 加载 catalog；已有请求在途时等待同一次请求，避免重复拉取与重复 hash 扫描。
    func refresh(force: Bool = false) async {
        if let refreshTask {
            await refreshTask.value
            return
        }
        isRefreshing = true
        if loadState == .idle {
            loadState = .loading
        }
        onChange?()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performRefresh(force: force)
        }
        refreshTask = task
        await task.value
        refreshTask = nil
        isRefreshing = false
        onChange?()
    }

    private func performRefresh(force: Bool) async {
        prepareIfNeeded()
        do {
            let snapshot = try await client.fetch(catalogURL: catalogURL,
                                                  forceRefresh: force)
            self.snapshot = snapshot
            reconcileState()
            rebuildRows()
            loadState = .loaded
        } catch {
            if snapshot == nil {
                loadState = .failed(error.localizedDescription)
            } else {
                loadState = .loaded
            }
            onError?(error.localizedDescription)
        }
    }

    /// 外部编辑器/Finder 改动模板目录后，重新计算本地 hash 与状态。
    func revalidateLocalFiles() {
        guard snapshot != nil else { return }
        rebuildRows()
        onChange?()
    }

    func categoryName(for id: String?) -> String {
        guard let id,
              let category = snapshot?.index.categoryList.first(where: { $0.id == id }) else {
            return id ?? ""
        }
        return category.name(preferredLanguages: LanguageTag.templatePreferredLanguages)
    }

    /// 按 id 查询目录行；catalog 未加载或模板不存在时返回 nil。
    func row(id: String) -> Row? {
        rows.first(where: { $0.entry.id == id })
    }

    /// 官网深链入口：按 id 安装目录中的最新版本。
    /// 已是最新则直接返回；本地有修改时先备份再安装，不静默覆盖用户改动。
    func installTemplate(id: String) async throws {
        await ensureLoaded()
        if row(id: id) == nil, snapshot != nil {
            await refresh(force: true)
        }
        guard let snapshot, !snapshot.isReadOnly else {
            throw ServiceError.catalogUnavailable
        }
        guard let row = row(id: id) else {
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
        guard let snapshot, !snapshot.isReadOnly else {
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

        let task = Task { () -> Result<Void, Error> in
            do {
                try await self.performInstall(
                    entry: entry,
                    catalogURL: snapshot.catalogURL,
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
        guard let snapshot,
              let page = row.entry.pageURLString(
                preferredLanguages: LanguageTag.templatePreferredLanguages),
              let url = URL(string: page, relativeTo: snapshot.catalogURL)?.absoluteURL else {
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
        if let entry = snapshot?.index.templates.first(where: { $0.file == file }) {
            return state.installed[entry.id]?.version
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
        guard let entry = snapshot?.index.templates.first(where: { $0.file == file }),
              state.installed[entry.id] != nil else { return nil }
        return entry.author
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
        guard let index = snapshot?.index, !stateReadOnly else { return }
        var changed = false
        for entry in index.templates {
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
                    sourceCatalog: catalogURL.absoluteString)
                changed = true
            }
        }
        if changed {
            try? stateStore.save(state)
        }
    }

    private func rebuildRows() {
        guard let index = snapshot?.index else {
            rows = []
            return
        }
        let appVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        rows = index.templates.sortedForLibrary().map { entry in
            let url = localURL(for: entry)
            let localHash = fileExists(url) ? try? FileDigest.sha256(of: url) : nil
            let record = state.installed[entry.id]
            let evaluation = TemplateLibraryEvaluator.evaluate(
                entry: entry,
                record: record,
                localSHA256: localHash,
                appVersion: appVersion,
                ignoredVersion: state.ignored[entry.id])
            return Row(entry: entry, evaluation: evaluation, record: record)
        }
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
