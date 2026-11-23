import XCTest
@testable import ClickBoom

final class RuntimeStatusTests: XCTestCase {
    func testEveryCombinationRespectsStatusPriority() {
        let app = ExcludedApp(bundleID: "test.app", name: "演示")
        for mask in 0..<32 {
            let enabled = mask & 1 != 0
            let paused = mask & 2 != 0
            let excluded = mask & 4 != 0
            let autoSilence = mask & 8 != 0
            let fullScreen = mask & 16 != 0
            let expected: RuntimeStatus
            switch (enabled, paused, excluded, autoSilence && fullScreen) {
            case (false, _, _, _): expected = .disabled
            case (_, true, _, _): expected = .paused
            case (_, _, true, _): expected = .excluded(appName: "演示")
            case (_, _, _, true): expected = .fullScreen(appName: "演示")
            default: expected = .running
            }
            XCTAssertEqual(RuntimeStatus.resolve(
                isEnabled: enabled, isPaused: paused,
                excludedApp: excluded ? app : nil, autoSilenceInFullScreen: autoSilence,
                isFullScreen: fullScreen, appName: app.name
            ), expected, "组合 \(mask)")
        }
    }

    func testQuietHoursOutranksExclusionAndFullScreenButNotPause() {
        let app = ExcludedApp(bundleID: "test.app", name: "演示")
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 22, minute: 30))!
        let quiet = QuietHours(isEnabled: true, startMinutes: 22 * 60, endMinutes: 8 * 60)

        func resolve(
            enabled: Bool = true,
            paused: Bool = false,
            quietHours: QuietHours = quiet
        ) -> RuntimeStatus {
            RuntimeStatus.resolve(
                isEnabled: enabled, isPaused: paused,
                quietHours: quietHours, now: now,
                excludedApp: app, autoSilenceInFullScreen: true,
                isFullScreen: true, appName: app.name
            )
        }

        XCTAssertEqual(resolve(), .quietHours(schedule: quiet.scheduleLabel))
        XCTAssertEqual(resolve(enabled: false), .disabled)
        XCTAssertEqual(resolve(paused: true), .paused)
        XCTAssertEqual(
            resolve(quietHours: QuietHours(isEnabled: true, startMinutes: 600, endMinutes: 600)),
            .excluded(appName: "演示")
        )
    }

    func testSkippedQuietHoursFallsThroughToNextReason() {
        let app = ExcludedApp(bundleID: "test.app", name: "演示")
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 22, minute: 30))!
        let quiet = QuietHours(isEnabled: true, startMinutes: 22 * 60, endMinutes: 8 * 60)

        let skipped = RuntimeStatus.resolve(
            isEnabled: true, isPaused: false,
            quietHours: quiet, isQuietHoursSkipped: true, now: now,
            excludedApp: nil, autoSilenceInFullScreen: false,
            isFullScreen: false, appName: "前台 App"
        )
        XCTAssertEqual(skipped, .running)

        let skippedButExcluded = RuntimeStatus.resolve(
            isEnabled: true, isPaused: false,
            quietHours: quiet, isQuietHoursSkipped: true, now: now,
            excludedApp: app, autoSilenceInFullScreen: false,
            isFullScreen: false, appName: app.name
        )
        XCTAssertEqual(skippedButExcluded, .excluded(appName: "演示"))
    }

    func testQuietHoursStopsAtEndMinute() {
        let calendar = Calendar.current
        let quiet = QuietHours(isEnabled: true, startMinutes: 22 * 60, endMinutes: 8 * 60)
        let atEnd = calendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 8, minute: 0))!
        let status = RuntimeStatus.resolve(
            isEnabled: true, isPaused: false,
            quietHours: quiet, now: atEnd, excludedApp: nil,
            autoSilenceInFullScreen: false, isFullScreen: false, appName: "前台 App"
        )
        XCTAssertEqual(status, .running)
    }
}
