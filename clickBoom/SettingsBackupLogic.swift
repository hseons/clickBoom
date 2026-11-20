import Foundation

/// 「设置备份」：快捷键、全屏静默开关、免打扰时段和排除列表的导出格式。
///
/// 故意和预设归档分成两个文件，以后单独调整预设 schema 时不会牵连到设置备份。
nonisolated struct SettingsBackup: Codable, Equatable {
    var schemaVersion: Int
    var hotKeySpec: String
    var hotKeyEnabled: Bool
    var autoSilenceInFullScreen: Bool
    var excludedApps: [ExcludedApp]
    /// 1.9 新增，可选是为了继续读 1.5–1.8 导出的旧备份。
    var quietHoursEnabled: Bool?
    var quietHoursStartMinutes: Int?
    var quietHoursEndMinutes: Int?

    init(
        schemaVersion: Int = SettingsBackupLogic.schemaVersion,
        hotKeySpec: String,
        hotKeyEnabled: Bool,
        autoSilenceInFullScreen: Bool,
        excludedApps: [ExcludedApp],
        quietHoursEnabled: Bool? = nil,
        quietHoursStartMinutes: Int? = nil,
        quietHoursEndMinutes: Int? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.hotKeySpec = hotKeySpec
        self.hotKeyEnabled = hotKeyEnabled
        self.autoSilenceInFullScreen = autoSilenceInFullScreen
        self.excludedApps = excludedApps
        self.quietHoursEnabled = quietHoursEnabled
        self.quietHoursStartMinutes = quietHoursStartMinutes
        self.quietHoursEndMinutes = quietHoursEndMinutes
    }

    /// 把备份里的免打扰字段合进当前设置；旧备份缺少这些字段时保持当前值。
    func applyingQuietHours(to quietHours: QuietHours) -> QuietHours {
        QuietHours(
            isEnabled: quietHoursEnabled ?? quietHours.isEnabled,
            startMinutes: quietHoursStartMinutes ?? quietHours.startMinutes,
            endMinutes: quietHoursEndMinutes ?? quietHours.endMinutes
        )
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
