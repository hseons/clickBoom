import Foundation

/// 面板、监听与覆盖层共用的生效规则，顺序就是提示的优先级。
nonisolated enum RuntimeStatus: Equatable {
    case disabled
    case permissionRequired
    case paused
    case quietHours(range: String)
    case excluded(appName: String)
    case fullScreen(appName: String)
    case running

    static func resolve(
        isEnabled: Bool,
        hasPermission: Bool,
        isPaused: Bool,
        quietHours: QuietHours = QuietHours(),
        now: Date = Date(),
        excludedApp: ExcludedApp?,
        autoSilenceInFullScreen: Bool,
        isFullScreen: Bool,
        appName: String
    ) -> RuntimeStatus {
        if !isEnabled { return .disabled }
        if !hasPermission { return .permissionRequired }
        if isPaused { return .paused }
        if quietHours.isActive(at: now) { return .quietHours(range: quietHours.rangeLabel) }
        if let excludedApp { return .excluded(appName: excludedApp.name) }
        if autoSilenceInFullScreen && isFullScreen { return .fullScreen(appName: appName) }
        return .running
    }

    var isRunning: Bool { self == .running }

    var title: String {
        switch self {
        case .disabled: return "特效已关闭"
        case .permissionRequired: return "等待输入监控权限"
        case .paused: return "特效已暂停"
        case .quietHours: return "免打扰时段静默中"
        case .excluded(let name): return "已在「\(name)」中静默"
        case .fullScreen(let name): return "「\(name)」全屏静默中"
        case .running: return "特效运行中"
        }
    }

    var icon: String {
        switch self {
        case .disabled: return "power"
        case .permissionRequired: return "exclamationmark.shield.fill"
        case .paused: return "pause.circle.fill"
        case .quietHours: return "moon.zzz.fill"
        case .excluded: return "eye.slash.fill"
        case .fullScreen: return "rectangle.expand.vertical"
        case .running: return "sparkles"
        }
    }
}
