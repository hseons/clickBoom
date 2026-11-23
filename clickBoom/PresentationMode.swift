import Foundation

/// 进入演示模式前的设置快照。
///
/// 演示模式会临时关掉「全屏静默」和「免打扰时段」，套一份更适合录屏的视觉参数；
/// 退出时必须精确还原，所以先把会被改动的字段整份记下来，而不是逐个 if 回滚。
nonisolated struct PresentationSnapshot: Equatable {
    var autoSilenceInFullScreen: Bool
    var quietHoursEnabled: Bool
    var quietHoursStartMinutes: Int
    var quietHoursEndMinutes: Int
    var quietHoursWeekdayMask: Int
    var spotlightEnabled: Bool
    var keystrokeHUDEnabled: Bool

    nonisolated init(
        autoSilenceInFullScreen: Bool,
        quietHoursEnabled: Bool,
        quietHoursStartMinutes: Int,
        quietHoursEndMinutes: Int,
        quietHoursWeekdayMask: Int,
        spotlightEnabled: Bool,
        keystrokeHUDEnabled: Bool
    ) {
        self.autoSilenceInFullScreen = autoSilenceInFullScreen
        self.quietHoursEnabled = quietHoursEnabled
        self.quietHoursStartMinutes = quietHoursStartMinutes
        self.quietHoursEndMinutes = quietHoursEndMinutes
        self.quietHoursWeekdayMask = quietHoursWeekdayMask
        self.spotlightEnabled = spotlightEnabled
        self.keystrokeHUDEnabled = keystrokeHUDEnabled
    }
}
