import XCTest
import AppKit
import Carbon
@testable import ClickBoom

final class HotKeySettingsTests: XCTestCase {
    func testDefaultSpecIsControlOptionB() {
        XCTAssertEqual(HotKeySpec.default.label, "⌃⌥B")
        XCTAssertTrue(HotKeySpec.default.isValid)
    }

    func testLabelAlwaysUsesControlOptionShiftCommandOrder() {
        let spec = HotKeySpec(
            keyCode: UInt32(kVK_ANSI_K),
            modifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey)
        )
        XCTAssertEqual(spec.label, "⌃⌥⇧⌘K")
    }

    func testFromRequiresAStrongModifier() {
        XCTAssertNil(HotKeySpec.from(keyCode: UInt16(kVK_ANSI_B), modifierFlags: []))

        let shiftOnly = HotKeySpec.from(keyCode: UInt16(kVK_ANSI_B), modifierFlags: [.shift])
        XCTAssertNil(shiftOnly, "只有 Shift 的组合太容易误触，不应被接受")

        let controlOnly = HotKeySpec.from(keyCode: UInt16(kVK_ANSI_B), modifierFlags: [.control])
        XCTAssertEqual(controlOnly?.label, "⌃B")

        let all = HotKeySpec.from(
            keyCode: UInt16(kVK_F5),
            modifierFlags: [.control, .option, .shift, .command]
        )
        XCTAssertEqual(all?.label, "⌃⌥⇧⌘F5")
    }

    func testStorageValueRoundTrip() {
        let spec = HotKeySpec(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(optionKey | cmdKey)
        )
        let restored = HotKeySpec(storageValue: spec.storageValue)
        XCTAssertEqual(restored, spec)
        XCTAssertEqual(restored?.label, "⌥⌘空格")
    }

    func testInvalidStorageFallsBackToNil() {
        XCTAssertNil(HotKeySpec(storageValue: nil))
        XCTAssertNil(HotKeySpec(storageValue: ""))
        XCTAssertNil(HotKeySpec(storageValue: "hello"))
        XCTAssertNil(HotKeySpec(storageValue: "11"))
        XCTAssertNil(HotKeySpec(storageValue: "11:"))
        XCTAssertNil(HotKeySpec(storageValue: "x:4352"))
        XCTAssertNil(HotKeySpec(storageValue: "11:0"), "没有修饰键的存储值应视为无效")
    }

    func testKeyNames() {
        XCTAssertEqual(HotKeySpec.keyName(for: UInt32(kVK_ANSI_A)), "A")
        XCTAssertEqual(HotKeySpec.keyName(for: UInt32(kVK_ANSI_7)), "7")
        XCTAssertEqual(HotKeySpec.keyName(for: UInt32(kVK_LeftArrow)), "←")
        XCTAssertEqual(HotKeySpec.keyName(for: UInt32(kVK_Return)), "↩")
        XCTAssertEqual(HotKeySpec.keyName(for: UInt32(kVK_F12)), "F12")
        XCTAssertEqual(HotKeySpec.keyName(for: 999), "键码 999")
    }
}
