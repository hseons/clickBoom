import XCTest
@testable import ClickBoom

final class ClickSoundTests: XCTestCase {
    func testGainKeepsEndpointsAndRisesMonotonically() {
        XCTAssertEqual(ClickSoundLogic.gain(volume: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(ClickSoundLogic.gain(volume: 1), 1, accuracy: 0.0001)

        var previous: Float = -1
        for step in stride(from: 0.0, through: 1.0, by: 0.05) {
            let value = ClickSoundLogic.gain(volume: step)
            XCTAssertGreaterThanOrEqual(value, previous)
            previous = value
        }
    }

    func testGainClampsOutOfRangeVolumes() {
        XCTAssertEqual(ClickSoundLogic.gain(volume: -3), 0, accuracy: 0.0001)
        XCTAssertEqual(ClickSoundLogic.gain(volume: 12), 1, accuracy: 0.0001)
    }

    func testDefaultVolumeSitsAtComfortableLevel() {
        XCTAssertEqual(ClickSoundLogic.defaultVolume, 0.35, accuracy: 0.0001)
        let gain = ClickSoundLogic.gain(volume: ClickSoundLogic.defaultVolume)
        XCTAssertGreaterThan(gain, 0.5)
        XCTAssertLessThan(gain, 0.7)
    }

    func testDebounceSuppressesBurstClicks() {
        XCTAssertFalse(ClickSoundLogic.shouldPlay(
            isEnabled: true, isRunning: true, secondsSinceLastPlay: 0.01
        ))
        XCTAssertTrue(ClickSoundLogic.shouldPlay(
            isEnabled: true, isRunning: true, secondsSinceLastPlay: 0.05
        ))
        XCTAssertTrue(ClickSoundLogic.shouldPlay(
            isEnabled: true, isRunning: true, secondsSinceLastPlay: ClickSoundLogic.debounceInterval
        ))
    }

    func testSilentStatesSkipPlayback() {
        XCTAssertFalse(ClickSoundLogic.shouldPlay(isEnabled: false, isRunning: true, secondsSinceLastPlay: 5))
        XCTAssertFalse(ClickSoundLogic.shouldPlay(isEnabled: true, isRunning: false, secondsSinceLastPlay: 5))
    }

    func testStylesCoverThreeTonesWithStableRawValues() {
        XCTAssertEqual(ClickSoundStyle.allCases.map(\.rawValue), ["click", "soft", "wood"])
        XCTAssertEqual(ClickSoundStyle.allCases.map(\.title), ["清脆", "柔和", "木质"])
        XCTAssertTrue(ClickSoundStyle.allCases.allSatisfy { !$0.detail.isEmpty })
        XCTAssertEqual(ClickSoundStyle(rawValue: "wood"), .wood)
    }
}
