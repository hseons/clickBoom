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
}
