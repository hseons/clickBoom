import XCTest
@testable import ClickBoom

final class RuntimeStatusTests: XCTestCase {
    func testEveryCombinationRespectsStatusPriority() {
        let app = ExcludedApp(bundleID: "test.app", name: "演示")
        for mask in 0..<64 {
            let enabled = mask & 1 != 0
            let granted = mask & 2 != 0
            let paused = mask & 4 != 0
            let excluded = mask & 8 != 0
            let autoSilence = mask & 16 != 0
            let fullScreen = mask & 32 != 0
            let expected: RuntimeStatus
            switch (enabled, granted, paused, excluded, autoSilence && fullScreen) {
            case (false, _, _, _, _): expected = .disabled
            case (_, false, _, _, _): expected = .permissionRequired
            case (_, _, true, _, _): expected = .paused
            case (_, _, _, true, _): expected = .excluded(appName: "演示")
            case (_, _, _, _, true): expected = .fullScreen(appName: "演示")
            default: expected = .running
            }
            XCTAssertEqual(RuntimeStatus.resolve(
                isEnabled: enabled, hasPermission: granted, isPaused: paused,
                excludedApp: excluded ? app : nil, autoSilenceInFullScreen: autoSilence,
                isFullScreen: fullScreen, appName: app.name
            ), expected, "组合 \(mask)")
        }
    }

    func testQuietHoursOutranksExclusionAndFullScreenButNotPause() {
        let app = ExcludedApp(bundleID: "test.app", name: "演示")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 22, minute: 30))!
        let quiet = QuietHours(isEnabled: true, startMinutes: 22 * 60, endMinutes: 8 * 60)

        func resolve(
            enabled: Bool = true,
            granted: Bool = true,
            paused: Bool = false,
            quietHours: QuietHours = quiet
        ) -> RuntimeStatus {
            RuntimeStatus.resolve(
                isEnabled: enabled, hasPermission: granted, isPaused: paused,
                quietHours: quietHours, now: now,
                excludedApp: app, autoSilenceInFullScreen: true,
                isFullScreen: true, appName: app.name
            )
        }

        XCTAssertEqual(resolve(), .quietHours(range: quiet.rangeLabel))
        XCTAssertEqual(resolve(enabled: false), .disabled)
        XCTAssertEqual(resolve(granted: false), .permissionRequired)
        XCTAssertEqual(resolve(paused: true), .paused)
        XCTAssertEqual(
            resolve(quietHours: QuietHours(isEnabled: true, startMinutes: 600, endMinutes: 600)),
            .excluded(appName: "演示")
        )
    }

    func testQuietHoursStopsAtEndMinute() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let quiet = QuietHours(isEnabled: true, startMinutes: 22 * 60, endMinutes: 8 * 60)
        let atEnd = calendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 8, minute: 0))!
        let status = RuntimeStatus.resolve(
            isEnabled: true, hasPermission: true, isPaused: false,
            quietHours: quiet, now: atEnd, excludedApp: nil,
            autoSilenceInFullScreen: false, isFullScreen: false, appName: "前台 App"
        )
        XCTAssertEqual(status, .running)
    }
}
