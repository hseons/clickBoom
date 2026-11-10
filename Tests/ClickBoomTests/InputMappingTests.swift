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
}
