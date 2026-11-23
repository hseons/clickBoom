import XCTest
@testable import ClickBoom

final class FullScreenLogicTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    func testWindowMatchingScreenIsFullScreen() {
        XCTAssertTrue(FullScreenLogic.isCoveringScreen(windowFrame: screen, screenFrame: screen))
    }

    func testWindowSmallerThanScreenIsNotFullScreen() {
        let window = CGRect(x: 0, y: 25, width: 1512, height: 957)
        XCTAssertFalse(FullScreenLogic.isCoveringScreen(windowFrame: window, screenFrame: screen))
    }

    func testOnePointToleranceIsAccepted() {
        let window = CGRect(x: -1, y: -1, width: 1514, height: 984)
        XCTAssertTrue(FullScreenLogic.isCoveringScreen(windowFrame: window, screenFrame: screen))
    }

    func testEmptyFramesAreNotFullScreen() {
        XCTAssertFalse(FullScreenLogic.isCoveringScreen(windowFrame: .zero, screenFrame: screen))
        XCTAssertFalse(FullScreenLogic.isCoveringScreen(windowFrame: screen, screenFrame: .zero))
    }

    func testSecondDisplayFullScreenIsDetected() {
        let external = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        XCTAssertTrue(
            FullScreenLogic.isCoveringAnyScreen(windowFrame: external, screenFrames: [screen, external])
        )
        let windowed = CGRect(x: 1600, y: 100, width: 800, height: 600)
        XCTAssertFalse(
            FullScreenLogic.isCoveringAnyScreen(windowFrame: windowed, screenFrames: [screen, external])
        )
    }

    func testAdjacentFullWidthWindowSegmentsCoverScreen() {
        let content = CGRect(x: 0, y: 0, width: 1512, height: 882)
        let toolbar = CGRect(x: 0, y: 882, width: 1512, height: 60)
        let titlebar = CGRect(x: 0, y: 942, width: 1512, height: 40)
        XCTAssertTrue(
            FullScreenLogic.isCoveredByWindowSegments(
                windowFrames: [content, toolbar, titlebar],
                screenFrames: [screen]
            )
        )
    }

    func testWindowSegmentsWithVerticalGapDoNotCoverScreen() {
        let content = CGRect(x: 0, y: 0, width: 1512, height: 882)
        let toolbar = CGRect(x: 0, y: 892, width: 1512, height: 90)
        XCTAssertFalse(
            FullScreenLogic.isCoveredByWindowSegments(
                windowFrames: [content, toolbar],
                screenFrames: [screen]
            )
        )
    }

    func testSideBySideWindowsDoNotCoverScreen() {
        let left = CGRect(x: 0, y: 0, width: 756, height: 982)
        let right = CGRect(x: 756, y: 0, width: 756, height: 982)
        XCTAssertFalse(
            FullScreenLogic.isCoveredByWindowSegments(
                windowFrames: [left, right],
                screenFrames: [screen]
            )
        )
    }

    func testCGWindowBoundsAreFlippedToAppKitCoordinates() {
        // 主屏高 982：CG 里 y=0 的窗口在 AppKit 中顶到 982，y=25 时下移 25
        let top = FullScreenLogic.appKitFrame(
            fromCGWindowBounds: CGRect(x: 0, y: 0, width: 1512, height: 982),
            primaryScreenHeight: 982
        )
        XCTAssertEqual(top, CGRect(x: 0, y: 0, width: 1512, height: 982))

        let lowered = FullScreenLogic.appKitFrame(
            fromCGWindowBounds: CGRect(x: 10, y: 25, width: 800, height: 600),
            primaryScreenHeight: 982
        )
        XCTAssertEqual(lowered, CGRect(x: 10, y: 357, width: 800, height: 600))
    }

    func testRecheckIntervalBacksOffOnlyAfterThirtyIdleSeconds() {
        XCTAssertEqual(FullScreenRecheckPolicy.interval(idleSeconds: 0), 0.5)
        XCTAssertEqual(FullScreenRecheckPolicy.interval(idleSeconds: 29.9), 0.5)
        XCTAssertEqual(FullScreenRecheckPolicy.interval(idleSeconds: 30), 2.0)
        XCTAssertEqual(FullScreenRecheckPolicy.interval(idleSeconds: 600), 2.0)
    }

    func testRecheckLabelDistinguishesIdleBackoff() {
        XCTAssertEqual(FullScreenRecheckPolicy.label(interval: 0.5), "0.5 秒")
        XCTAssertEqual(FullScreenRecheckPolicy.label(interval: 2.0), "2.0 秒（静止退避）")
    }
}
