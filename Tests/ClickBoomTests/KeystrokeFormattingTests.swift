import Carbon
import XCTest
@testable import ClickBoom

final class KeystrokeFormattingTests: XCTestCase {
    func testModifierSymbolsUseFixedOrder() {
        XCTAssertEqual(
            KeystrokeFormatting.modifierSymbols(control: true, option: true, shift: true, command: true),
            "⌃⌥⇧⌘"
        )
        XCTAssertEqual(
            KeystrokeFormatting.modifierSymbols(control: false, option: false, shift: true, command: true),
            "⇧⌘"
        )
        XCTAssertEqual(
            KeystrokeFormatting.modifierSymbols(control: false, option: false, shift: false, command: false),
            ""
        )
        XCTAssertEqual(
            KeystrokeFormatting.modifierSymbols(control: false, option: false, shift: false, command: false, function: true),
            "fn"
        )
    }

    func testKeyLabelPrefersTypedCharacter() {
        XCTAssertEqual(KeystrokeFormatting.keyLabel(keyCode: UInt32(kVK_ANSI_A), characters: "a"), "A")
        XCTAssertEqual(KeystrokeFormatting.keyLabel(keyCode: UInt32(kVK_ANSI_1), characters: "1"), "1")
    }

    func testSpaceAndControlCharactersFallBackToReadableNames() {
        XCTAssertEqual(KeystrokeFormatting.keyLabel(keyCode: UInt32(kVK_Space), characters: " "), "空格")
        XCTAssertFalse(
            KeystrokeFormatting.keyLabel(keyCode: UInt32(kVK_Return), characters: "\r").isEmpty
        )
        XCTAssertEqual(
            KeystrokeFormatting.keyLabel(keyCode: UInt32(kVK_Escape), characters: "\u{1B}"),
            HotKeySpec.keyName(for: UInt32(kVK_Escape))
        )
    }

    func testModifierKeyCodesAreRecognised() {
        let modifiers = [kVK_Command, kVK_RightCommand, kVK_Shift, kVK_RightShift,
                         kVK_Option, kVK_RightOption, kVK_Control, kVK_RightControl,
                         kVK_Function, kVK_CapsLock]
        for code in modifiers {
            XCTAssertTrue(KeystrokeFormatting.isModifierKeyCode(UInt32(code)), "键码 \(code) 应算修饰键")
        }
        XCTAssertFalse(KeystrokeFormatting.isModifierKeyCode(UInt32(kVK_ANSI_A)))
    }

    func testShortcutsOnlyModeHidesPlainTyping() {
        XCTAssertTrue(KeystrokeFormatting.shouldDisplay(modifiers: "", showShortcutsOnly: false))
        XCTAssertFalse(KeystrokeFormatting.shouldDisplay(modifiers: "", showShortcutsOnly: true))
        XCTAssertTrue(KeystrokeFormatting.shouldDisplay(modifiers: "⌘", showShortcutsOnly: true))
    }

    func testSecureInputIsNeverDisplayed() {
        XCTAssertFalse(KeystrokeFormatting.shouldDisplay(isSecureInput: true))
        XCTAssertTrue(KeystrokeFormatting.shouldDisplay(isSecureInput: false))
    }

    func testEventTextConcatenatesModifiersAndKey() {
        let shortcut = KeystrokeEvent(keyLabel: "P", modifiers: "⌃⌥", isModifierOnly: false)
        let modifierOnly = KeystrokeEvent(keyLabel: "", modifiers: "⌘", isModifierOnly: true)

        XCTAssertEqual(shortcut.text, "⌃⌥P")
        XCTAssertEqual(modifierOnly.text, "⌘")
        XCTAssertFalse(shortcut.isSecureInput)
    }

    func testChipLayoutLimitsThreePerRow() {
        XCTAssertEqual(KeystrokeFormatting.maxChipsPerRow, 3)
    }

    func testHUDSizesProvideThreeScaleSteps() {
        XCTAssertEqual(KeystrokeHUDSize.allCases.map(\.rawValue), [0, 1, 2])
        XCTAssertEqual(KeystrokeHUDSize.allCases.map(\.title), ["小", "中", "大"])
        XCTAssertLessThan(KeystrokeHUDSize.small.scale, KeystrokeHUDSize.medium.scale)
        XCTAssertLessThan(KeystrokeHUDSize.medium.scale, KeystrokeHUDSize.large.scale)
    }
}
