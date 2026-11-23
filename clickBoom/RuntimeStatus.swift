import Foundation

/// 面板、监听与覆盖层共用的生效规则，顺序就是提示的优先级。
nonisolated enum RuntimeStatus: Equatable {
    case disabled
    case paused
    case quietHours(schedule: String)
    case excluded(appName: String)
    case fullScreen(appName: String)
    case presenting
    case running

    static func resolve(
        isEnabled: Bool,
        isPaused: Bool,
        isPresentationMode: Bool = false,
        quietHours: QuietHours = QuietHours(),
        isQuietHoursSkipped: Bool = false,
        now: Date = Date(),
        excludedApp: ExcludedApp?,
        autoSilenceInFullScreen: Bool,
        isFullScreen: Bool,
        appName: String
    ) -> RuntimeStatus {
        if !isEnabled { return .disabled }
        if isPaused { return .paused }
        // 演示模式：全屏和免打扰都不再静默，但应用排除仍然尊重。
        if isPresentationMode {
            if let excludedApp { return .excluded(appName: excludedApp.name) }
            return .presenting
        }
        if !isQuietHoursSkipped, quietHours.isActive(at: now) {
            return .quietHours(schedule: quietHours.scheduleLabel)
        }
        if let excludedApp { return .excluded(appName: excludedApp.name) }
        if autoSilenceInFullScreen && isFullScreen { return .fullScreen(appName: appName) }
        return .running
    }

    var isRunning: Bool { self == .running || self == .presenting }

    var title: String {
        switch self {
        case .disabled: return "特效已关闭"
        case .paused: return "特效已暂停"
        case .quietHours: return "免打扰时段静默中"
        case .excluded(let name): return "已在「\(name)」中静默"
        case .fullScreen(let name): return "「\(name)」全屏静默中"
        case .presenting: return "演示模式运行中"
        case .running: return "特效运行中"
        }
    }

    var icon: String {
        switch self {
        case .disabled: return "power"
        case .paused: return "pause.circle.fill"
        case .quietHours: return "moon.zzz.fill"
        case .excluded: return "eye.slash.fill"
        case .fullScreen: return "rectangle.expand.vertical"
        case .presenting: return "person.wave.2.fill"
        case .running: return "sparkles"
        }
    }
}
