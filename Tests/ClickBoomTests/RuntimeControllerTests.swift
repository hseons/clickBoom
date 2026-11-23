import AppKit
import Combine
import XCTest
@testable import ClickBoom

final class RuntimeControllerTests: XCTestCase {
    @MainActor
    private func withRuntime(_ body: (AppState, EffectEngine, InputPermission, RuntimeController,
                                     (RuntimeContext) -> Void, (CGPoint) -> Void, (Bool) -> Void) throws -> Void) rethrows {
        let suite = "ClickBoomTests.Runtime.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = AppState(defaults: defaults)
        state.spotlightEnabled = true
        state.trailEnabled = true
        let engine = EffectEngine(state: state)
        var granted = true
        let permission = InputPermission(checkAccess: { granted })
        var context = RuntimeContext(app: ExcludedApp(bundleID: "test.editor", name: "编辑器"),
                                     isFullScreen: false, screenCount: 2)
        var pointer = CGPoint(x: 12, y: 34)
        let runtime = RuntimeController(state: state, permission: permission, engine: engine,
                                        monitor: nil, context: { _ in context }, pointer: { pointer })
        defer { runtime.stop(); state.resume() }
        try body(state, engine, permission, runtime, { context = $0 }, { pointer = $0 }, { granted = $0 })
    }

    @MainActor
    func testExclusionClearsAllEffectsAndRestoresAtCurrentPointer() {
        withRuntime { state, engine, _, runtime, setContext, setPointer, _ in
            runtime.refresh()
            engine.trigger(at: CGPoint(x: 1, y: 2))
            XCTAssertFalse(engine.particles.isEmpty)
            XCTAssertFalse(engine.trailPoints.isEmpty)
            XCTAssertNotNil(engine.spotlightPulseStart)
            let excluded = ExcludedApp(bundleID: "test.movie", name: "播放器")
            state.excludedApps = [excluded]
            setContext(RuntimeContext(app: excluded, isFullScreen: true, screenCount: 2))
            runtime.refresh()
            XCTAssertEqual(runtime.status, .excluded(appName: "播放器"))
            XCTAssertTrue(engine.particles.isEmpty)
            XCTAssertTrue(engine.trailPoints.isEmpty)
            XCTAssertNil(engine.pointerPosition)
            XCTAssertNil(engine.spotlightPulseStart)
            setPointer(CGPoint(x: 500, y: 600))
            setContext(RuntimeContext(app: ExcludedApp(bundleID: "test.editor", name: "编辑器"),
                                      isFullScreen: false, screenCount: 2))
            runtime.refresh()
            XCTAssertEqual(runtime.status, .running)
            XCTAssertEqual(engine.pointerPosition, CGPoint(x: 500, y: 600))
            XCTAssertTrue(engine.trailPoints.isEmpty)
        }
    }

    @MainActor
    func testFullScreenExitAndSwitchingAppsReevaluateStatus() {
        withRuntime { state, engine, _, runtime, setContext, setPointer, _ in
            let movie = ExcludedApp(bundleID: "test.movie", name: "播放器")
            setContext(RuntimeContext(app: movie, isFullScreen: true, screenCount: 1))
            runtime.refresh()
            XCTAssertEqual(runtime.status, .fullScreen(appName: "播放器"))
            XCTAssertNil(engine.pointerPosition)
            setPointer(CGPoint(x: 80, y: 90))
            setContext(RuntimeContext(app: movie, isFullScreen: false, screenCount: 1))
            runtime.refresh()
            XCTAssertEqual(runtime.status, .running)
            XCTAssertEqual(engine.pointerPosition, CGPoint(x: 80, y: 90))
            setContext(RuntimeContext(app: movie, isFullScreen: true, screenCount: 1))
            state.autoSilenceInFullScreen = false
            runtime.refresh()
            XCTAssertEqual(runtime.status, .running)
        }
    }

    @MainActor
    func testPauseAndPermissionRevocationClearAndRestore() {
        withRuntime { state, engine, permission, runtime, _, setPointer, setGranted in
            runtime.refresh()
            engine.trigger(at: .zero)
            state.pause(minutes: 15)
            runtime.refresh()
            XCTAssertEqual(runtime.status, .paused)
            XCTAssertTrue(engine.particles.isEmpty)
            XCTAssertNil(engine.pointerPosition)
            setGranted(false)
            permission.refresh()
            runtime.refresh()
            XCTAssertEqual(runtime.status, .permissionRequired)
            state.resume()
            runtime.refresh()
            XCTAssertEqual(runtime.status, .permissionRequired)
            setPointer(CGPoint(x: 200, y: 300))
            setGranted(true)
            permission.refresh()
            runtime.refresh()
            XCTAssertEqual(runtime.status, .running)
            XCTAssertEqual(engine.pointerPosition, CGPoint(x: 200, y: 300))
        }
    }

    @MainActor
    func testScreenChangeResetsCoordinatesAndRestoresPointerWithoutOldTrail() {
        withRuntime { _, engine, _, runtime, _, setPointer, _ in
            runtime.refresh()
            engine.trigger(at: .zero)
            setPointer(CGPoint(x: 1800, y: 100))
            runtime.refresh(forceFullScreen: true, resetEffects: true)
            XCTAssertTrue(engine.particles.isEmpty)
            XCTAssertTrue(engine.trailPoints.isEmpty)
            XCTAssertNil(engine.spotlightPulseStart)
            XCTAssertEqual(engine.pointerPosition, CGPoint(x: 1800, y: 100))
        }
    }

    @MainActor
    func testPreviewRemainsAvailableWhileDisabledAndPauseStillBlocksNormalInput() {
        withRuntime { state, engine, _, runtime, _, _, _ in
            state.isEnabled = false
            state.trailEnabled = false
            runtime.refresh()
            engine.trigger(at: .zero)
            XCTAssertTrue(engine.particles.isEmpty)
            engine.preview(at: .zero)
            XCTAssertFalse(engine.particles.isEmpty)
            state.isEnabled = true
            state.pause(minutes: 15)
            runtime.refresh()
            XCTAssertTrue(engine.particles.isEmpty)
            engine.trigger(at: .zero)
            XCTAssertTrue(engine.particles.isEmpty)
            engine.preview(at: .zero)
            XCTAssertFalse(engine.particles.isEmpty)
        }
    }

    @MainActor
    func testDiagnosticsReadCountsAndDoNotChangeSavedSettings() {
        withRuntime { state, engine, _, runtime, _, _, _ in
            runtime.refresh()
            engine.trigger(at: .zero)
            let settings = state.settingsBackup()
            let particles = engine.particles.count
            let trail = engine.trailPoints.count
            let snapshot = runtime.diagnostics()
            XCTAssertEqual(snapshot.screenCount, 2)
            XCTAssertEqual(snapshot.appName, "编辑器")
            XCTAssertEqual(snapshot.particleCount, particles)
            XCTAssertEqual(snapshot.trailPointCount, trail)
            XCTAssertTrue(snapshot.permissionGranted)
            XCTAssertEqual(state.settingsBackup(), settings)
        }
    }

    @MainActor
    func testSettingsSubscriptionReadsNewValueAndStopsWithOwner() async {
        let suite = "ClickBoomTests.Runtime.Subscription.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = AppState(defaults: defaults)
        state.autoSilenceInFullScreen = false
        let permission = InputPermission(checkAccess: { true })
        let engine = EffectEngine(state: state)
        var reads = 0
        let runtime = RuntimeController(state: state, permission: permission, engine: engine, monitor: nil,
                                        context: { _ in
                                            reads += 1
                                            return RuntimeContext(app: nil, isFullScreen: false, screenCount: 1)
                                        }, pointer: { .zero })
        runtime.start()
        let changed = expectation(description: "设置写入后状态同步")
        var subscription: AnyCancellable? = runtime.$status.dropFirst().sink { status in
            if status == .disabled { changed.fulfill() }
        }
        state.isEnabled = false
        await fulfillment(of: [changed], timeout: 2)
        XCTAssertEqual(runtime.status, .disabled)
        subscription?.cancel()
        subscription = nil
        runtime.stop()
        let stoppedReads = reads
        state.isEnabled = true
        // 主队列屏障：已取消的设置订阅不再投递。
        let drained = expectation(description: "主队列已处理")
        RunLoop.main.perform { drained.fulfill() }
        await fulfillment(of: [drained], timeout: 2)
        XCTAssertEqual(reads, stoppedReads)
    }

    @MainActor
    func testWakeNotificationRefreshesWithoutResumingPause() async {
        let suite = "ClickBoomTests.Runtime.Wake.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = AppState(defaults: defaults)
        state.autoSilenceInFullScreen = false
        let permission = InputPermission(checkAccess: { true })
        let engine = EffectEngine(state: state)
        var reads = 0
        let runtime = RuntimeController(
            state: state,
            permission: permission,
            engine: engine,
            monitor: nil,
            context: { _ in
                reads += 1
                return RuntimeContext(app: nil, isFullScreen: false, screenCount: 1)
            },
            pointer: { .zero }
        )
        defer { runtime.stop(); state.resume() }

        runtime.start()
        state.pause(minutes: 15)
        runtime.refresh()
        XCTAssertEqual(runtime.status, .paused)
        let readsBeforeWake = reads

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

        let drained = expectation(description: "唤醒通知已处理")
        RunLoop.main.perform { drained.fulfill() }
        await fulfillment(of: [drained], timeout: 2)

        XCTAssertGreaterThan(reads, readsBeforeWake)
        XCTAssertEqual(runtime.status, .paused)
    }

    @MainActor
    func testClearCancelsQueuedTrailPreviewFrames() async {
        let suite = "ClickBoomTests.Runtime.Preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = AppState(defaults: defaults)
        state.trailEnabled = true
        let engine = EffectEngine(state: state)
        engine.previewTrailOnly(at: .zero)
        engine.clearEffects()
        let framesDrained = expectation(description: "预览最后一帧投递时间已过")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { framesDrained.fulfill() }
        await fulfillment(of: [framesDrained], timeout: 2)
        XCTAssertTrue(engine.trailPoints.isEmpty)
        XCTAssertNil(engine.pointerPosition)
    }

    @MainActor
    func testQuietHoursSilencesAndRestoresAtBoundary() {
        let suite = "ClickBoomTests.Runtime.Quiet.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = AppState(defaults: defaults)
        state.autoSilenceInFullScreen = false
        state.trailEnabled = true
        state.quietHoursEnabled = true
        state.quietHoursStartMinutes = 22 * 60
        state.quietHoursEndMinutes = 8 * 60
        let permission = InputPermission(checkAccess: { true })
        let engine = EffectEngine(state: state)
        let calendar = Calendar.current
        var current = calendar.date(
            from: DateComponents(year: 2026, month: 11, day: 20, hour: 22, minute: 30)
        )!
        let runtime = RuntimeController(
            state: state,
            permission: permission,
            engine: engine,
            monitor: nil,
            context: { _ in RuntimeContext(app: nil, isFullScreen: false, screenCount: 1) },
            pointer: { CGPoint(x: 40, y: 50) },
            now: { current }
        )
        defer { runtime.stop(); state.resume() }

        engine.trigger(at: CGPoint(x: 1, y: 1))
        runtime.refresh()
        XCTAssertEqual(runtime.status, .quietHours(schedule: "每天 22:00 – 次日 08:00"))
        XCTAssertTrue(engine.particles.isEmpty)
        XCTAssertTrue(engine.trailPoints.isEmpty)

        current = calendar.date(
            from: DateComponents(year: 2026, month: 11, day: 21, hour: 8, minute: 0)
        )!
        runtime.refresh()
        XCTAssertEqual(runtime.status, .running)
        XCTAssertEqual(engine.pointerPosition, CGPoint(x: 40, y: 50))
    }

    @MainActor
    func testSkipQuietHoursOnceRestoresUntilBoundaryThenClears() {
        let suite = "ClickBoomTests.Runtime.Skip.\\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = AppState(defaults: defaults)
        state.autoSilenceInFullScreen = false
        state.trailEnabled = true
        state.quietHoursEnabled = true
        state.quietHoursStartMinutes = 22 * 60
        state.quietHoursEndMinutes = 8 * 60
        let engine = EffectEngine(state: state)
        let calendar = Calendar.current
        var current = calendar.date(
            from: DateComponents(year: 2026, month: 11, day: 20, hour: 22, minute: 30)
        )!
        let runtime = RuntimeController(
            state: state,
            permission: InputPermission(checkAccess: { true }),
            engine: engine,
            monitor: nil,
            context: { _ in RuntimeContext(app: nil, isFullScreen: false, screenCount: 1) },
            pointer: { CGPoint(x: 40, y: 50) },
            now: { current }
        )
        defer { runtime.stop(); state.resume() }

        runtime.refresh()
        XCTAssertEqual(runtime.status, .quietHours(schedule: state.quietHours.scheduleLabel))
        XCTAssertTrue(runtime.skipQuietHoursOnce())
        XCTAssertEqual(state.quietHoursSkipUntil,
                       calendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 8, minute: 0)))
        XCTAssertEqual(runtime.status, .running)
        XCTAssertEqual(engine.pointerPosition, CGPoint(x: 40, y: 50))

        // 同一个时段里再点一次不再重复设置，仍保持放行。
        XCTAssertFalse(runtime.skipQuietHoursOnce())
        current = calendar.date(
            from: DateComponents(year: 2026, month: 11, day: 21, hour: 3, minute: 0)
        )!
        runtime.refresh()
        XCTAssertEqual(runtime.status, .running)

        // 到结束边界后跳过记录自动清掉，下一次时段照常静默。
        current = calendar.date(
            from: DateComponents(year: 2026, month: 11, day: 21, hour: 8, minute: 0)
        )!
        runtime.refresh()
        XCTAssertNil(state.quietHoursSkipUntil)
        current = calendar.date(
            from: DateComponents(year: 2026, month: 11, day: 21, hour: 22, minute: 10)
        )!
        runtime.refresh()
        XCTAssertEqual(runtime.status, .quietHours(schedule: state.quietHours.scheduleLabel))
    }

    @MainActor
    func testSkipQuietHoursOnlyWorksInsideActiveWindowAndPersists() {
        let suite = "ClickBoomTests.Runtime.SkipPersist.\\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = AppState(defaults: defaults)
        state.quietHoursEnabled = true
        state.quietHoursStartMinutes = 22 * 60
        state.quietHoursEndMinutes = 8 * 60
        state.quietHoursWeekdayMask = QuietHours.weekdaysMask

        let noon = Calendar.current.date(
            from: DateComponents(year: 2026, month: 11, day: 20, hour: 12, minute: 0)
        )!
        XCTAssertFalse(state.skipQuietHoursOnce(at: noon))

        let night = Calendar.current.date(
            from: DateComponents(year: 2026, month: 11, day: 20, hour: 23, minute: 0)
        )!
        XCTAssertTrue(state.skipQuietHoursOnce(at: night))
        XCTAssertEqual(state.quietHoursWeekdayMask, QuietHours.weekdaysMask)
        XCTAssertNotNil(defaults.object(forKey: "quietHoursWeekdays"))
        XCTAssertNotNil(defaults.object(forKey: "quietHoursSkipUntil"))

        let reloaded = AppState(defaults: defaults)
        XCTAssertEqual(reloaded.quietHoursWeekdayMask, QuietHours.weekdaysMask)
        XCTAssertEqual(reloaded.quietHoursSkipUntil, state.quietHoursSkipUntil)
        reloaded.clearQuietHoursSkip()
        XCTAssertNil(reloaded.quietHoursSkipUntil)
        XCTAssertNil(defaults.object(forKey: "quietHoursSkipUntil"))
    }
}
