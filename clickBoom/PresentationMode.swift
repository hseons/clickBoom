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

/// 演示模式的纯规则：什么时候算生效、进入时改哪些值、退出时还原成什么。
enum PresentationModeLogic {
    /// 演示模式只在特效本来该工作时才「顶掉」静默规则；
    /// 关闭、缺权限、暂停这三种情况仍然优先，避免按了快捷键却看不到任何反馈。
    nonisolated static func isActive(
        isPresentationMode: Bool,
        isEnabled: Bool,
        hasPermission: Bool,
        isPaused: Bool
    ) -> Bool {
        isPresentationMode && isEnabled && hasPermission && !isPaused
    }

    /// 演示模式生效时是否要继续走免打扰 / 全屏静默的判断。
    nonisolated static func shouldApplySilenceRules(isActive: Bool) -> Bool {
        !isActive
    }
}
