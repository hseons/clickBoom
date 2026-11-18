import AppKit
import Combine

struct RuntimeContext {
    var app: ExcludedApp?
    var isFullScreen: Bool
    var screenCount: Int

    /// 面板成为前台时，继续显示最近外部应用的生效原因。
    static func current(forceRefresh: Bool) -> RuntimeContext {
        let tracker = FrontmostAppTracker.shared
        tracker.refreshFromFrontmost()
        let frontmost = NSWorkspace.shared.frontmostApplication
        let target = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            ? tracker.lastActiveApplication : frontmost
        let app = target.flatMap { target -> ExcludedApp? in
            guard !target.isTerminated else { return nil }
            let id = target.bundleIdentifier ?? "pid:\(target.processIdentifier)"
            return ExcludedApp(bundleID: id, name: target.localizedName ?? id)
        }
        let state = AppState.shared
        let needsFullScreenCheck = state.isEnabled && InputPermission.shared.isGranted && !state.isPaused
            && state.autoSilenceInFullScreen
            && !AppExclusionLogic.isExcluded(bundleID: app?.bundleID, in: state.excludedApps)
        return RuntimeContext(
            app: app,
            isFullScreen: app != nil && needsFullScreenCheck
                && FullScreenDetector.shared.isAppFullScreen(target, forceRefresh: forceRefresh),
            screenCount: NSScreen.screens.count
        )
    }
}

/// 生效状态和全局监听的唯一所有者，生命周期跟随应用。
@MainActor
final class RuntimeController: ObservableObject {
    static let shared = RuntimeController()

    @Published private(set) var status: RuntimeStatus = .disabled
    @Published private(set) var targetApp: ExcludedApp?

    private let state: AppState
    private let permission: InputPermission
    private let engine: EffectEngine
    private let monitor: GlobalMouseMonitor?
    private let context: (Bool) -> RuntimeContext
    private let pointer: () -> CGPoint?
    private var subscriptions: Set<AnyCancellable> = []
    private var spaceRefresh: Task<Void, Never>?
    private var fullScreenTimer: Timer?
    private var started = false
    private var hadPermission = false

    convenience init() {
        self.init(state: .shared, permission: .shared, engine: .shared,
                  monitor: GlobalMouseMonitor(),
                  context: { RuntimeContext.current(forceRefresh: $0) },
                  pointer: { OverlayGeometry.mousePoint() })
    }

    init(
        state: AppState,
        permission: InputPermission,
        engine: EffectEngine,
        monitor: GlobalMouseMonitor?,
        context: @escaping (Bool) -> RuntimeContext,
        pointer: @escaping () -> CGPoint?
    ) {
        self.state = state
        self.permission = permission
        self.engine = engine
        self.monitor = monitor
        self.context = context
        self.pointer = pointer
    }

    func start() {
        guard !started else { return }
        started = true
        hadPermission = permission.isGranted
        monitor?.start { [weak self] in
            guard let self else { return false }
            self.refresh()
            return self.status.isRunning
        }

        // @Published 在写入前发送，切到下一个主线程回合再读取完整设置。
        Publishers.MergeMany([
            state.$isEnabled.map { _ in () }.eraseToAnyPublisher(),
            state.$pauseUntil.map { _ in () }.eraseToAnyPublisher(),
            state.$excludedApps.map { _ in () }.eraseToAnyPublisher(),
            state.$autoSilenceInFullScreen.map { _ in () }.eraseToAnyPublisher(),
            state.$clickTriggerMode.map { _ in () }.eraseToAnyPublisher(),
            state.$rightClickEnabled.map { _ in () }.eraseToAnyPublisher(),
            state.$trailEnabled.map { _ in () }.eraseToAnyPublisher(),
            state.$spotlightEnabled.map { _ in () }.eraseToAnyPublisher(),
            permission.$isGranted.map { _ in () }.eraseToAnyPublisher()
        ])
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.refresh() }
        .store(in: &subscriptions)

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didWakeNotification] {
            workspace.publisher(for: name)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.environmentChanged() }
                .store(in: &subscriptions)
        }
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.environmentChanged() }
            .store(in: &subscriptions)
        refresh(forceFullScreen: true, resetEffects: true)
    }

    private func environmentChanged() {
        permission.refresh()
        FullScreenDetector.shared.invalidate()
        refresh(forceFullScreen: true, resetEffects: true)
        // 全屏切换通知可能早于窗口动画结束，再做一次有界复查。
        spaceRefresh?.cancel()
        spaceRefresh = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            self?.refresh(forceFullScreen: true)
        }
    }

    func refresh(forceFullScreen: Bool = false, resetEffects: Bool = false) {
        let snapshot = context(forceFullScreen)
        let excluded = snapshot.app.flatMap { app in
            AppExclusionLogic.isExcluded(bundleID: app.bundleID, in: state.excludedApps) ? app : nil
        }
        let next = RuntimeStatus.resolve(
            isEnabled: state.isEnabled,
            hasPermission: permission.isGranted,
            isPaused: state.isPaused,
            excludedApp: excluded,
            autoSilenceInFullScreen: state.autoSilenceInFullScreen,
            isFullScreen: snapshot.isFullScreen,
            appName: snapshot.app?.name ?? "前台 App"
        )
        let changed = next != status
        let targetChanged = targetApp != snapshot.app
        if targetChanged { targetApp = snapshot.app }
        if resetEffects || targetChanged || (changed && !next.isRunning) {
            monitor?.cancelPendingClicks()
            engine.clearEffects()
        }
        if changed { status = next }

        if permission.isGranted != hadPermission {
            hadPermission = permission.isGranted
            if hadPermission { monitor?.resetMonitors() }
        }
        monitor?.syncClicks(mode: state.clickTriggerMode, rightClickEnabled: state.rightClickEnabled,
                            isRunning: next.isRunning, engine: engine)
        let needsMotion = next.isRunning && (state.trailEnabled || state.spotlightEnabled)
        let wasMonitoring = monitor?.hasMotionMonitor == true
        monitor?.syncMotion(enabled: needsMotion, engine: engine)
        if needsMotion, resetEffects || targetChanged || changed || !wasMonitoring,
           let point = pointer() {
            engine.updatePointer(at: point, shouldExtendTrail: false)
        }

        // 静默时已释放移动监听；低频检查让同一空间内的全屏退出和静止指针也能恢复。
        // 关闭、无权限、暂停或排除时停止检查。诊断面板不拥有此计时器。
        let needsFullScreenCheck = state.isEnabled && permission.isGranted && !state.isPaused
            && excluded == nil && snapshot.app != nil && state.autoSilenceInFullScreen
        if started && needsFullScreenCheck && fullScreenTimer == nil {
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.permission.refresh()
                    self?.refresh(forceFullScreen: true)
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            fullScreenTimer = timer
        } else if !needsFullScreenCheck {
            fullScreenTimer?.invalidate()
            fullScreenTimer = nil
        }
    }

    func diagnostics() -> RuntimeDiagnostics {
        permission.refresh()
        refresh(forceFullScreen: true)
        return RuntimeDiagnostics(
            capturedAt: Date(),
            status: status.title,
            permissionGranted: permission.isGranted,
            appName: targetApp?.name ?? "暂无外部应用",
            bundleID: targetApp?.bundleID ?? "—",
            screenCount: context(false).screenCount,
            motionActive: monitor?.hasMotionMonitor == true,
            particleCount: engine.particles.count,
            trailPointCount: engine.trailPoints.count
        )
    }

    func stop() {
        started = false
        subscriptions.removeAll()
        spaceRefresh?.cancel()
        spaceRefresh = nil
        fullScreenTimer?.invalidate()
        fullScreenTimer = nil
        monitor?.stop()
        engine.clearEffects()
    }
}

struct RuntimeDiagnostics {
    let capturedAt: Date
    let status: String
    let permissionGranted: Bool
    let appName: String
    let bundleID: String
    let screenCount: Int
    let motionActive: Bool
    let particleCount: Int
    let trailPointCount: Int
}
