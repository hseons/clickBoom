import XCTest
@testable import ClickBoom

@MainActor
final class PresentationModeTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "clickBoom.presentation.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func makeState() -> AppState {
        AppState(defaults: defaults)
    }

    func testEnterTurnsOffSilenceRulesAndTurnsOnVisualCues() {
        let state = makeState()
        state.autoSilenceInFullScreen = true
        state.quietHoursEnabled = true
        state.spotlightEnabled = false
        state.keystrokeHUDEnabled = false

        state.enterPresentationMode()

        XCTAssertTrue(state.isPresentationMode)
        XCTAssertFalse(state.autoSilenceInFullScreen)
        XCTAssertFalse(state.quietHoursEnabled)
        XCTAssertTrue(state.spotlightEnabled)
        XCTAssertTrue(state.keystrokeHUDEnabled)
    }

    func testExitRestoresEveryTouchedSetting() {
        let state = makeState()
        state.autoSilenceInFullScreen = true
        state.quietHoursEnabled = true
        state.quietHoursStartMinutes = 22 * 60
        state.quietHoursEndMinutes = 7 * 60
        state.quietHoursWeekdayMask = 0b000_1111
        state.spotlightEnabled = false
        state.keystrokeHUDEnabled = false

        state.enterPresentationMode()
        state.exitPresentationMode()

        XCTAssertFalse(state.isPresentationMode)
        XCTAssertTrue(state.autoSilenceInFullScreen)
        XCTAssertTrue(state.quietHoursEnabled)
        XCTAssertEqual(state.quietHoursStartMinutes, 22 * 60)
        XCTAssertEqual(state.quietHoursEndMinutes, 7 * 60)
        XCTAssertEqual(state.quietHoursWeekdayMask, 0b000_1111)
        XCTAssertFalse(state.spotlightEnabled)
        XCTAssertFalse(state.keystrokeHUDEnabled)
    }

    func testEnteringTwiceKeepsTheFirstSnapshot() {
        let state = makeState()
        state.autoSilenceInFullScreen = true
        state.spotlightEnabled = false

        state.enterPresentationMode()
        state.enterPresentationMode()
        state.exitPresentationMode()

        XCTAssertTrue(state.autoSilenceInFullScreen)
        XCTAssertFalse(state.spotlightEnabled)
        XCTAssertFalse(state.isPresentationMode)
    }

    func testExitingWithoutEnteringChangesNothing() {
        let state = makeState()
        state.autoSilenceInFullScreen = true
        state.keystrokeHUDEnabled = false

        state.exitPresentationMode()

        XCTAssertFalse(state.isPresentationMode)
        XCTAssertTrue(state.autoSilenceInFullScreen)
        XCTAssertFalse(state.keystrokeHUDEnabled)
    }

    func testPresentationModeIsNeverPersisted() {
        let state = makeState()
        state.enterPresentationMode()
        XCTAssertTrue(state.isPresentationMode)

        let reloaded = makeState()

        XCTAssertFalse(reloaded.isPresentationMode)
        XCTAssertFalse(reloaded.autoSilenceInFullScreen, "演示模式改过的全屏静默不该被写进磁盘")
    }

    func testPresentationHotKeyDefaultsToControlOptionP() {
        let state = makeState()

        XCTAssertEqual(state.presentationHotKeySpec, .presentationDefault)
        XCTAssertEqual(state.presentationHotKeySpec.label, "⌃⌥P")
        XCTAssertTrue(state.presentationHotkeyEnabled)
    }

    func testPresentationHotKeyRoundTripsThroughStorage() {
        let spec = HotKeySpec(keyCode: 40, modifiers: HotKeySpec.supportedModifiers)
        let restored = HotKeySpec(storageValue: spec.storageValue)

        XCTAssertEqual(restored, spec)
        XCTAssertEqual(HotKeySlot.presentation.rawValue, 2)
        XCTAssertEqual(HotKeySlot.toggle.rawValue, 1)
    }

    func testPresentationStatusSkipsQuietHoursAndFullScreen() {
        let app = ExcludedApp(bundleID: "test.app", name: "演示")
        let quietHours = QuietHours(isEnabled: true, startMinutes: 0, endMinutes: 23 * 60 + 59)

        let presenting = RuntimeStatus.resolve(
            isEnabled: true,
            isPaused: false,
            isPresentationMode: true,
            quietHours: quietHours,
            excludedApp: nil,
            autoSilenceInFullScreen: true,
            isFullScreen: true,
            appName: "Keynote"
        )

        XCTAssertEqual(presenting, .presenting)
        XCTAssertTrue(presenting.isRunning)
        XCTAssertEqual(presenting.title, "演示模式运行中")
    }

    func testPresentationStatusStillRespectsPauseAndExclusion() {
        let app = ExcludedApp(bundleID: "test.app", name: "演示")

        XCTAssertEqual(
            RuntimeStatus.resolve(
                isEnabled: true, isPaused: true, isPresentationMode: true,
                excludedApp: nil, autoSilenceInFullScreen: false, isFullScreen: false, appName: "Keynote"
            ),
            .paused
        )
        XCTAssertEqual(
            RuntimeStatus.resolve(
                isEnabled: true, isPaused: false, isPresentationMode: true,
                excludedApp: app, autoSilenceInFullScreen: false, isFullScreen: false, appName: "Keynote"
            ),
            .excluded(appName: "演示")
        )
    }
}
