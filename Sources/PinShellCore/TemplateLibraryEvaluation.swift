import Foundation

public enum TemplateLibraryInstallState: String, Sendable, Equatable {
    /// 本地没有同名文件，也没有安装记录。
    case notInstalled
    /// 文件与 state 记录匹配（可能被用户编辑，见 `isEdited`）。
    case installed
    /// 本地有同名文件，但没有安装记录（用户手动放入或旧版本）。
    case unmanagedLocal
}

public struct TemplateLibraryEvaluation: Equatable, Sendable {
    public var remoteVersion: String
    public var installedVersion: String?
    public var installState: TemplateLibraryInstallState
    public var isEdited: Bool
    public var updateAvailable: Bool
    public var isRepair: Bool
    public var isIgnored: Bool
    public var needsNewerApp: Bool

    public init(remoteVersion: String,
                installedVersion: String? = nil,
                installState: TemplateLibraryInstallState,
                isEdited: Bool = false,
                updateAvailable: Bool = false,
                isRepair: Bool = false,
                isIgnored: Bool = false,
                needsNewerApp: Bool = false) {
        self.remoteVersion = remoteVersion
        self.installedVersion = installedVersion
        self.installState = installState
        self.isEdited = isEdited
        self.updateAvailable = updateAvailable
        self.isRepair = isRepair
        self.isIgnored = isIgnored
        self.needsNewerApp = needsNewerApp
    }
}

/// 纯函数判定：catalog entry + 本地 state + 本地文件 hash + App 版本。
public enum TemplateLibraryEvaluator {
    public static func evaluate(entry: TemplateLibraryEntry,
                                record: InstalledTemplateRecord?,
                                localSHA256: String?,
                                appVersion: String,
                                ignoredVersion: String? = nil) -> TemplateLibraryEvaluation {
        let needsNewerApp = VersionNumber.compare(entry.minimumAppVersion, appVersion)
            == .orderedDescending
        let isIgnored = ignoredVersion == entry.version

        guard let record, let localSHA256 else {
            if record == nil, localSHA256 != nil {
                return TemplateLibraryEvaluation(
                    remoteVersion: entry.version,
                    installState: .unmanagedLocal,
                    isIgnored: isIgnored,
                    needsNewerApp: needsNewerApp
                )
            }
            // 没有记录，或记录对应的文件已被删除：都视为可重新安装。
            // 忽略记录只阻止“更新”，不阻止重新安装一个不存在的模板。
            return TemplateLibraryEvaluation(
                remoteVersion: entry.version,
                installState: .notInstalled,
                updateAvailable: !needsNewerApp,
                isIgnored: isIgnored,
                needsNewerApp: needsNewerApp
            )
        }

        let comparison = VersionNumber.compare(entry.version, record.version)
        let isRepair = comparison == .orderedSame && entry.payload.sha256 != record.sha256
        let hasNewerVersion = comparison == .orderedDescending
        let updateAvailable = (hasNewerVersion || isRepair) && !needsNewerApp && !isIgnored

        return TemplateLibraryEvaluation(
            remoteVersion: entry.version,
            installedVersion: record.version,
            installState: .installed,
            isEdited: localSHA256 != record.sha256,
            updateAvailable: updateAvailable,
            isRepair: isRepair,
            isIgnored: isIgnored,
            needsNewerApp: needsNewerApp
        )
    }
}
