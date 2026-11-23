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
        let needsFullScreenCheck = state.isEnabled && !state.isPaused
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
    private let now: () -> Date
    private var subscriptions: Set<AnyCancellable> = []
    private var spaceRefresh: Task<Void, Never>?
    private var fullScreenTimer: Timer?
    private var fullScreenRecheckInterval: TimeInterval = 0
    private var quietHoursTimer: Timer?
    private var quietHoursBoundary: Date?
    private var started = false
    private var hadPermission = false
    /// 上一次为目标应用套用的预设，避免每帧刷新都把用户手动改动覆盖掉。
    private var appliedPresetID: UUID?

    convenience init() {
        self.init(state: .shared, permission: .shared, engine: .shared,
                  monitor: GlobalMouseMonitor(),
                  context: { RuntimeContext.current(forceRefresh: $0) },
                  pointer: { OverlayGeometry.mousePoint() },
                  now: { Date() })
    }

    init(
        state: AppState,
        permission: InputPermission,
        engine: EffectEngine,
        monitor: GlobalMouseMonitor?,
        context: @escaping (Bool) -> RuntimeContext,
        pointer: @escaping () -> CGPoint?,
        now: @escaping () -> Date = { Date() }
    ) {
        self.state = state
        self.permission = permission
        self.engine = engine
        self.monitor = monitor
        self.context = context
        self.pointer = pointer
        self.now = now
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
            state.$appRules.map { _ in () }.eraseToAnyPublisher(),
            state.$isPresentationMode.map { _ in () }.eraseToAnyPublisher(),
            state.$autoSilenceInFullScreen.map { _ in () }.eraseToAnyPublisher(),
            state.$quietHoursEnabled.map { _ in () }.eraseToAnyPublisher(),
            state.$quietHoursStartMinutes.map { _ in () }.eraseToAnyPublisher(),
            state.$quietHoursEndMinutes.map { _ in () }.eraseToAnyPublisher(),
            state.$quietHoursWeekdayMask.map { _ in () }.eraseToAnyPublisher(),
            state.$quietHoursSkipUntil.map { _ in () }.eraseToAnyPublisher(),
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
        // 跳过到期后就地清掉，避免下次启动还带着一个过期的放行时间。
        state.clearExpiredQuietHoursSkip(at: now())
        let snapshot = context(forceFullScreen)
        let excluded = snapshot.app.flatMap { app in
            AppExclusionLogic.isExcluded(bundleID: app.bundleID, in: state.excludedApps) ? app : nil
        }
        let next = RuntimeStatus.resolve(
            isEnabled: state.isEnabled,
            isPaused: state.isPaused,
            isPresentationMode: state.isPresentationMode,
            quietHours: state.quietHours,
            isQuietHoursSkipped: state.isQuietHoursSkipped(at: now()),
            now: now(),
            excludedApp: excluded,
            autoSilenceInFullScreen: state.autoSilenceInFullScreen,
            isFullScreen: snapshot.isFullScreen,
            appName: snapshot.app?.name ?? "前台 App"
        )
        state.trailSuppressedForCurrentApp = AppRuleLogic.disablesTrail(
            for: snapshot.app?.bundleID,
            in: state.appRules
        )
        let changed = next != status
        let targetChanged = targetApp != snapshot.app
        if targetChanged { targetApp = snapshot.app }
        if targetChanged { applyRulePreset(for: snapshot.app) }
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
        let needsMotion = next.isRunning && (state.isTrailActive || state.spotlightEnabled)
        let wasMonitoring = monitor?.hasMotionMonitor == true
        monitor?.syncMotion(enabled: needsMotion, engine: engine)
        if needsMotion, resetEffects || targetChanged || changed || !wasMonitoring,
           let point = pointer() {
            engine.updatePointer(at: point, shouldExtendTrail: false)
        }

        // 静默时已释放移动监听；低频检查让同一空间内的全屏退出和静止指针也能恢复。
        // 关闭、无权限、暂停或排除时停止检查。诊断面板不拥有此计时器。
        // 免打扰时段内不复查全屏：这段时间本来就不显示特效，时段结束时由边界计时器恢复。
        let inQuietHours = state.quietHours.isActive(at: now())
            && !state.isQuietHoursSkipped(at: now())
        let needsFullScreenCheck = state.isEnabled && !state.isPaused
            && !state.isPresentationMode
            && !inQuietHours
            && excluded == nil && snapshot.app != nil && state.autoSilenceInFullScreen
        syncFullScreenTimer(needed: needsFullScreenCheck)

        syncQuietHoursTimer()
    }

    /// 切换到某个应用时按规则套用它的预设；离开后不强制还原，避免把用户手改的参数顶掉。
    private func applyRulePreset(for app: ExcludedApp?) {
        guard let presetID = AppRuleLogic.presetID(for: app?.bundleID, in: state.appRules) else {
            appliedPresetID = nil
            return
        }
        guard presetID != appliedPresetID else { return }
        guard let preset = state.savedPresets.first(where: { $0.id == presetID }) else { return }
        appliedPresetID = presetID
        state.apply(preset)
    }

    /// 「本次跳过」：放行当前免打扰时段，到下一个边界自动恢复规则。
    @discardableResult
    func skipQuietHoursOnce() -> Bool {
        guard state.skipQuietHoursOnce(at: now()) else { return false }
        refresh(forceFullScreen: true, resetEffects: true)
        return true
    }

    /// 全屏复查按有没有输入换挡：连续静止 30 秒后从 0.5 秒退到 2 秒，
    /// 指针一动就回到 0.5 秒。计时器本身不重建，只在间隔变化时换一个。
    private func syncFullScreenTimer(needed: Bool) {
        guard started, needed else {
            fullScreenTimer?.invalidate()
            fullScreenTimer = nil
            fullScreenRecheckInterval = 0
            return
        }
        let desired = FullScreenRecheckPolicy.interval(idleSeconds: recentInputIdleSeconds())
        guard fullScreenTimer == nil || abs(desired - fullScreenRecheckInterval) > 0.001 else { return }
        fullScreenTimer?.invalidate()
        let timer = Timer(timeInterval: desired, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.fullScreenTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        fullScreenTimer = timer
        fullScreenRecheckInterval = desired
    }

    private func fullScreenTick() {
        let desired = FullScreenRecheckPolicy.interval(idleSeconds: recentInputIdleSeconds())
        if abs(desired - fullScreenRecheckInterval) > 0.001 {
            syncFullScreenTimer(needed: true)
        }
        permission.refresh()
        refresh(forceFullScreen: true)
    }

    /// 鼠标最近一次移动、按下或拖拽距今多少秒；键盘和触控板事件不计入。
    private func recentInputIdleSeconds() -> TimeInterval {
        let source = CGEventSourceStateID.combinedSessionState
        let idle = [
            CGEventSource.secondsSinceLastEventType(source, eventType: .mouseMoved),
            CGEventSource.secondsSinceLastEventType(source, eventType: .leftMouseDown),
            CGEventSource.secondsSinceLastEventType(source, eventType: .leftMouseDragged),
            CGEventSource.secondsSinceLastEventType(source, eventType: .rightMouseDown)
        ]
        return idle.min() ?? 0
    }

    /// 免打扰只安排下一次边界的一次性计时器，平时不轮询；系统唤醒和设置变化都会重建。
    private func syncQuietHoursTimer() {
        let quietHours = state.quietHours
        guard started, let boundary = quietHours.nextBoundary(after: now()) else {
            quietHoursTimer?.invalidate()
            quietHoursTimer = nil
            quietHoursBoundary = nil
            return
        }
        if quietHoursBoundary == boundary, quietHoursTimer != nil { return }
        quietHoursTimer?.invalidate()
        let timer = Timer(fire: boundary, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.quietHoursTimer = nil
                self?.quietHoursBoundary = nil
                self?.refresh(forceFullScreen: true)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        quietHoursTimer = timer
        quietHoursBoundary = boundary
    }

    func diagnostics() -> RuntimeDiagnostics {
        permission.refresh()
        refresh(forceFullScreen: true)
        let budget = EffectBudgetStore.shared
        let budgetSnapshot = budget.currentSnapshot
        let tier = budget.tier
        let frameCost: String
        if let p90 = budgetSnapshot.liveP90Millis, budgetSnapshot.liveSampleCount > 0 {
            frameCost = String(format: "p90 %.1f ms（%d 帧）", p90, budgetSnapshot.liveSampleCount)
        } else if let last = budgetSnapshot.lastP90Millis {
            frameCost = String(format: "p90 %.1f ms（上次采样）", last)
        } else {
            frameCost = "暂无活动帧"
        }
        let stallText = budgetSnapshot.stallRatio > 0.05
            ? String(format: "，卡帧 %.0f%%", budgetSnapshot.stallRatio * 100)
            : ""
        let tierText = tier.title
            + (budget.isPinned ? "（已固定）" : budgetSnapshot.isDegraded ? "（自动降级）" : "")
        let budgetText = "粒子 \(tier.particleLimit) · 轨迹 \(tier.trailPointLimit) · "
            + "\(Int((1.0 / tier.frameInterval).rounded())) fps"

        return RuntimeDiagnostics(
            capturedAt: Date(),
            status: status.title,
            permissionGranted: permission.isGranted,
            appName: targetApp?.name ?? "暂无外部应用",
            quietHours: quietHoursSummary,
            bundleID: targetApp?.bundleID ?? "—",
            screenCount: context(false).screenCount,
            motionActive: monitor?.hasMotionMonitor == true,
            particleCount: engine.particles.count,
            trailPointCount: engine.trailPoints.count,
            performanceTier: tierText,
            frameCost: frameCost + stallText,
            budgetLimits: budgetText,
            fullScreenRecheck: fullScreenRecheckSummary
        )
    }

    /// 复查间隔只在计时器运行时才有意义；打开诊断时顺带说明是否已退避。
    private var fullScreenRecheckSummary: String {
        guard fullScreenTimer != nil else { return "未运行" }
        return FullScreenRecheckPolicy.label(interval: fullScreenRecheckInterval)
    }

    private var quietHoursSummary: String {
        guard state.quietHours.isEnabled else { return "未开启" }
        let text = state.quietHours.scheduleLabel
        guard state.quietHours.isActive(at: now()) else { return text }
        return text + (state.isQuietHoursSkipped(at: now()) ? "（本次已跳过）" : "（生效中）")
    }

    func stop() {
        started = false
        subscriptions.removeAll()
        spaceRefresh?.cancel()
        spaceRefresh = nil
        fullScreenTimer?.invalidate()
        fullScreenTimer = nil
        quietHoursTimer?.invalidate()
        quietHoursTimer = nil
        quietHoursBoundary = nil
        monitor?.stop()
        engine.clearEffects()
    }
}

struct RuntimeDiagnostics {
    let capturedAt: Date
    let status: String
    let permissionGranted: Bool
    let appName: String
    let quietHours: String
    let bundleID: String
    let screenCount: Int
    let motionActive: Bool
    let particleCount: Int
    let trailPointCount: Int
    let performanceTier: String
    let frameCost: String
    let budgetLimits: String
    let fullScreenRecheck: String
}
