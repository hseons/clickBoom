import Foundation

/// 「设置备份」：快捷键、全屏静默开关和排除列表的导出格式。
///
/// 故意和预设归档分成两个文件，以后单独调整预设 schema 时不会牵连到设置备份。
nonisolated struct SettingsBackup: Codable, Equatable {
    var schemaVersion: Int
    var hotKeySpec: String
    var hotKeyEnabled: Bool
    var autoSilenceInFullScreen: Bool
    var excludedApps: [ExcludedApp]

    init(
        schemaVersion: Int = SettingsBackupLogic.schemaVersion,
        hotKeySpec: String,
        hotKeyEnabled: Bool,
        autoSilenceInFullScreen: Bool,
        excludedApps: [ExcludedApp]
    ) {
        self.schemaVersion = schemaVersion
        self.hotKeySpec = hotKeySpec
        self.hotKeyEnabled = hotKeyEnabled
        self.autoSilenceInFullScreen = autoSilenceInFullScreen
        self.excludedApps = excludedApps
    }
}

enum SettingsBackupLogic {
    nonisolated static let schemaVersion = 1

    nonisolated static func encode(_ backup: SettingsBackup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    /// 读进来的版本比当前新时直接拒绝，避免把不认识的字段当成默认值吞掉。
    nonisolated static func decode(_ data: Data) throws -> SettingsBackup {
        let backup = try JSONDecoder().decode(SettingsBackup.self, from: data)
        guard backup.schemaVersion <= schemaVersion else {
            throw SettingsBackupError.unsupportedVersion(backup.schemaVersion)
        }
        return backup
    }

    /// 合并导入的排除列表：逐条走 adding，顺带去重、更新名称、拒绝把 ClickBoom 自己排除。
    nonisolated static func mergingExclusions(
        _ apps: [ExcludedApp],
        ownBundleID: String? = Bundle.main.bundleIdentifier
    ) -> [ExcludedApp] {
        apps.reduce(into: [ExcludedApp]()) { result, app in
            result = AppExclusionLogic.adding(app, to: result, ownBundleID: ownBundleID)
        }
    }
}

enum SettingsBackupError: LocalizedError, Equatable {
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "这个备份来自更新的版本（schema \(version)），当前版本读不了。"
        }
    }
}
