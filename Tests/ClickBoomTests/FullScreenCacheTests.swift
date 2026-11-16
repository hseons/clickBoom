import XCTest
@testable import ClickBoom

final class FullScreenCacheTests: XCTestCase {
    @MainActor
    func testCacheUsesApplicationAndScreenIdentityAndExpires() {
        var date = Date(timeIntervalSince1970: 100)
        var calls = 0
        let detector = FullScreenDetector(query: { pid, _ in calls += 1; return pid == 1 }, now: { date })
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        XCTAssertTrue(detector.isFullScreen(processID: 1, screenFrames: [screen]))
        XCTAssertTrue(detector.isFullScreen(processID: 1, screenFrames: [screen]))
        XCTAssertEqual(calls, 1)
        // 同一缓存周期内切换应用，必须重新查询。
        XCTAssertFalse(detector.isFullScreen(processID: 2, screenFrames: [screen]))
        XCTAssertEqual(calls, 2)
        let second = CGRect(x: 1000, y: 0, width: 800, height: 1000)
        XCTAssertFalse(detector.isFullScreen(processID: 2, screenFrames: [screen, second]))
        XCTAssertEqual(calls, 3)
        date = date.addingTimeInterval(0.5)
        XCTAssertFalse(detector.isFullScreen(processID: 2, screenFrames: [screen, second]))
        XCTAssertEqual(calls, 4)
        detector.invalidate()
        XCTAssertFalse(detector.isFullScreen(processID: 2, screenFrames: [screen, second]))
        XCTAssertEqual(calls, 5)
        XCTAssertFalse(detector.isFullScreen(processID: 2, screenFrames: [screen, second], forceRefresh: true))
        XCTAssertEqual(calls, 6)
    }

    @MainActor
    func testMissingApplicationOrScreensInvalidatesPreviousResult() {
        var result = true
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let detector = FullScreenDetector(query: { _, _ in result })
        XCTAssertTrue(detector.isFullScreen(processID: 1, screenFrames: [screen]))
        XCTAssertFalse(detector.isFullScreen(processID: nil, screenFrames: [screen]))
        result = false
        XCTAssertFalse(detector.isFullScreen(processID: 1, screenFrames: [screen]))
        XCTAssertFalse(detector.isFullScreen(processID: 1, screenFrames: []))
        result = true
        XCTAssertTrue(detector.isFullScreen(processID: 1, screenFrames: [screen]))
    }
}
