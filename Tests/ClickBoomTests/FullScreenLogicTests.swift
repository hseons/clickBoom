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
}
