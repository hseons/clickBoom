import XCTest
@testable import ClickBoom

final class InputMappingTests: XCTestCase {
    @MainActor
    func testMouseButtonsMapToExpectedKindsAndPermission() {
        XCTAssertTrue(InputMapping.supports(.leftDown, rightClickEnabled: false))
        XCTAssertFalse(InputMapping.supports(.rightDown, rightClickEnabled: false))
        XCTAssertFalse(InputMapping.supports(.otherDown, rightClickEnabled: false))
        XCTAssertTrue(InputMapping.supports(.rightDown, rightClickEnabled: true))

        XCTAssertEqual(InputMapping.buttonKind(for: .leftDown), .left)
        XCTAssertEqual(InputMapping.buttonKind(for: .rightDown), .right)
        XCTAssertEqual(InputMapping.buttonKind(for: .otherDown), .middle)
    }

    @MainActor
    func testTrailTriggerModes() {
        XCTAssertFalse(InputMapping.shouldExtendTrail(
            for: .mouseMoved,
            triggerMode: .always,
            optionPressed: false,
            commandPressed: false,
            trailEnabled: false,
            rightClickEnabled: true
        ))
        XCTAssertTrue(InputMapping.shouldExtendTrail(
            for: .mouseMoved,
            triggerMode: .always,
            optionPressed: false,
            commandPressed: false,
            trailEnabled: true,
            rightClickEnabled: true
        ))
        XCTAssertFalse(InputMapping.shouldExtendTrail(
            for: .mouseMoved,
            triggerMode: .dragging,
            optionPressed: false,
            commandPressed: false,
            trailEnabled: true,
            rightClickEnabled: true
        ))
        XCTAssertTrue(InputMapping.shouldExtendTrail(
            for: .leftDrag,
            triggerMode: .dragging,
            optionPressed: false,
            commandPressed: false,
            trailEnabled: true,
            rightClickEnabled: true
        ))
        XCTAssertTrue(InputMapping.shouldExtendTrail(
            for: .mouseMoved,
            triggerMode: .optionKey,
            optionPressed: true,
            commandPressed: false,
            trailEnabled: true,
            rightClickEnabled: true
        ))
        XCTAssertFalse(InputMapping.shouldExtendTrail(
            for: .mouseMoved,
            triggerMode: .commandKey,
            optionPressed: true,
            commandPressed: false,
            trailEnabled: true,
            rightClickEnabled: true
        ))
        XCTAssertTrue(InputMapping.shouldExtendTrail(
            for: .mouseMoved,
            triggerMode: .commandKey,
            optionPressed: false,
            commandPressed: true,
            trailEnabled: true,
            rightClickEnabled: true
        ))
    }

    @MainActor
    func testDisabledRightClickSuppressesRightAndMiddleDragsOnly() {
        XCTAssertFalse(InputMapping.shouldExtendTrail(
            for: .rightDrag,
            triggerMode: .always,
            optionPressed: false,
            commandPressed: false,
            trailEnabled: true,
            rightClickEnabled: false
        ))
        XCTAssertFalse(InputMapping.shouldExtendTrail(
            for: .otherDrag,
            triggerMode: .always,
            optionPressed: false,
            commandPressed: false,
            trailEnabled: true,
            rightClickEnabled: false
        ))
        XCTAssertTrue(InputMapping.shouldExtendTrail(
            for: .leftDrag,
            triggerMode: .always,
            optionPressed: false,
            commandPressed: false,
            trailEnabled: true,
            rightClickEnabled: false
        ))
    }

    @MainActor
    private func click(
        _ phase: ClickInput.Phase,
        at time: TimeInterval = 0,
        count: Int = 1,
        location: CGPoint = .zero,
        kind: PointerInputKind = .leftDown,
        button: Int = 0
    ) -> ClickInput {
        ClickInput(phase: phase, kind: kind, buttonNumber: button, clickCount: count,
                   timestamp: time, location: location)
    }

    @MainActor
    func testSingleClickStillFiresOnEveryMouseDown() {
        var gesture = ClickGesture()
        XCTAssertEqual(gesture.receive(click(.down, count: 1), mode: .singleClick, rightClickEnabled: true), .left)
        XCTAssertEqual(gesture.receive(click(.down, count: 2), mode: .singleClick, rightClickEnabled: true), .left)
        XCTAssertNil(gesture.receive(click(.up), mode: .singleClick, rightClickEnabled: true))
    }

    @MainActor
    func testDoubleClickUsesSecondMouseDownAndKeepsButtonMapping() {
        var gesture = ClickGesture()
        for count in [0, 1, 3] {
            XCTAssertNil(gesture.receive(click(.down, count: count), mode: .doubleClick, rightClickEnabled: true))
        }
        XCTAssertEqual(gesture.receive(click(.down, count: 2), mode: .doubleClick, rightClickEnabled: false), .left)
        let right = click(.down, count: 2, kind: .rightDown, button: 1)
        XCTAssertEqual(gesture.receive(right, mode: .doubleClick, rightClickEnabled: true), .right)
        XCTAssertNil(gesture.receive(right, mode: .doubleClick, rightClickEnabled: false))
        XCTAssertNil(gesture.receive(click(.up, count: 2), mode: .doubleClick, rightClickEnabled: true))
    }

    @MainActor
    func testLongPressFiresOnlyOnceOnReleaseAtHalfSecond() {
        var gesture = ClickGesture()
        XCTAssertNil(gesture.receive(click(.down), mode: .longPress, rightClickEnabled: true))
        XCTAssertNil(gesture.receive(click(.up, at: 0.499), mode: .longPress, rightClickEnabled: true))
        XCTAssertNil(gesture.receive(click(.down, at: 1), mode: .longPress, rightClickEnabled: true))
        XCTAssertNil(gesture.receive(click(.dragged, at: 1.5, location: CGPoint(x: 2, y: 1)),
                                     mode: .longPress, rightClickEnabled: true))
        XCTAssertEqual(gesture.receive(click(.up, at: 1.5, location: CGPoint(x: 2, y: 1)),
                                       mode: .longPress, rightClickEnabled: true), .left)
        XCTAssertNil(gesture.receive(click(.up, at: 2), mode: .longPress, rightClickEnabled: true))
    }

    @MainActor
    func testDraggingPastToleranceCancelsEvenAfterMovingBack() {
        var gesture = ClickGesture()
        _ = gesture.receive(click(.down), mode: .longPress, rightClickEnabled: true)
        XCTAssertNil(gesture.receive(click(.dragged, at: 0.7, location: CGPoint(x: 6, y: 0)),
                                     mode: .longPress, rightClickEnabled: true))
        XCTAssertNil(gesture.receive(click(.up, at: 1), mode: .longPress, rightClickEnabled: true))
        _ = gesture.receive(click(.down, at: 2), mode: .longPress, rightClickEnabled: true)
        XCTAssertNil(gesture.receive(click(.up, at: 3, location: CGPoint(x: 5, y: 5)),
                                     mode: .longPress, rightClickEnabled: true))
    }

    @MainActor
    func testLongPressTracksPhysicalButtonsIndependently() {
        var gesture = ClickGesture()
        _ = gesture.receive(click(.down, kind: .otherDown, button: 2), mode: .longPress, rightClickEnabled: true)
        _ = gesture.receive(click(.down, at: 0.75, kind: .otherDown, button: 3),
                            mode: .longPress, rightClickEnabled: true)
        XCTAssertNil(gesture.receive(click(.up, at: 1, kind: .otherDown, button: 3),
                                     mode: .longPress, rightClickEnabled: true))
        XCTAssertEqual(gesture.receive(click(.up, at: 1, kind: .otherDown, button: 2),
                                       mode: .longPress, rightClickEnabled: true), .middle)
    }

    @MainActor
    func testResetAndDisabledButtonsDoNotLeaveAPendingPress() {
        var gesture = ClickGesture()
        _ = gesture.receive(click(.down), mode: .longPress, rightClickEnabled: true)
        gesture.reset()
        XCTAssertNil(gesture.receive(click(.up, at: 1), mode: .longPress, rightClickEnabled: true))
        _ = gesture.receive(click(.down, kind: .rightDown, button: 1), mode: .longPress, rightClickEnabled: false)
        XCTAssertNil(gesture.receive(click(.up, at: 1, kind: .rightDown, button: 1),
                                     mode: .longPress, rightClickEnabled: true))
    }

    @MainActor
    func testStaleReleaseDoesNotClearNewerPress() {
        var gesture = ClickGesture()
        _ = gesture.receive(click(.down, at: 2), mode: .longPress, rightClickEnabled: true)
        XCTAssertNil(gesture.receive(click(.up, at: 1.5), mode: .longPress, rightClickEnabled: true))
        XCTAssertEqual(gesture.receive(click(.up, at: 2.5), mode: .longPress, rightClickEnabled: true), .left)
    }

    @MainActor
    func testMissingOrUnknownTriggerModeFallsBackAndSelectionPersists() {
        let suite = "ClickBoomTests.ClickTrigger.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(AppState(defaults: defaults).clickTriggerMode, .singleClick)
        defaults.set("future-mode", forKey: "clickTriggerMode")
        let state = AppState(defaults: defaults)
        XCTAssertEqual(state.clickTriggerMode, .singleClick)
        state.clickTriggerMode = .doubleClick
        state.apply(.tutorial)
        XCTAssertEqual(AppState(defaults: defaults).clickTriggerMode, .doubleClick)
    }
}
