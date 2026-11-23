import AppKit
import Carbon

/// 全局快捷键的按键 + 修饰键组合。
///
/// 抽成纯值类型后，录制、文案展示、持久化和 Carbon 注册共用同一份规则，
/// 可以直接用单元测试覆盖「哪些组合能被接受」这类边界情况。
struct HotKeySpec: Equatable {
    /// 虚拟键码（`kVK_*`）
    var keyCode: UInt32
    /// Carbon 修饰键位：controlKey / optionKey / shiftKey / cmdKey
    var modifiers: UInt32

    nonisolated init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    nonisolated static let supportedModifiers = UInt32(controlKey | optionKey | shiftKey | cmdKey)
    /// 至少要有一个「强力」修饰键，避免把单独的方向键、字母抢成全局快捷键。
    nonisolated static let requiredModifiers = UInt32(controlKey | optionKey | cmdKey)

    nonisolated static let `default` = HotKeySpec(
        keyCode: UInt32(kVK_ANSI_B),
        modifiers: UInt32(controlKey | optionKey)
    )

    /// 演示模式默认 ⌃⌥P。
    nonisolated static let presentationDefault = HotKeySpec(
        keyCode: UInt32(kVK_ANSI_P),
        modifiers: UInt32(controlKey | optionKey)
    )

    /// 是否是可以注册的组合：带 ⌃ / ⌥ / ⌘ 之一，且键码不是纯修饰键。
    nonisolated var isValid: Bool {
        modifiers & Self.requiredModifiers != 0
    }

    /// 展示文案，例如「⌃⌥B」；修饰键固定按 ⌃⌥⇧⌘ 的顺序排列。
    nonisolated var label: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + Self.keyName(for: keyCode)
    }

    /// 录制时把 AppKit 的修饰键转换成 Carbon 位；不合格的组合返回 nil，录制继续等待。
    nonisolated static func from(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> HotKeySpec? {
        var carbonModifiers: UInt32 = 0
        if modifierFlags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if modifierFlags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if modifierFlags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        if modifierFlags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }

        let spec = HotKeySpec(keyCode: UInt32(keyCode), modifiers: carbonModifiers)
        return spec.isValid ? spec : nil
    }

    /// 存进 UserDefaults 的紧凑格式，例如 "11:4352"
    nonisolated var storageValue: String {
        "\(keyCode):\(modifiers)"
    }

    /// 从存储值恢复；格式不对或没有 ⌃/⌥/⌘ 时返回 nil，调用方回退到默认快捷键。
    nonisolated init?(storageValue: String?) {
        guard let storageValue else { return nil }
        let parts = storageValue.split(separator: ":")
        guard parts.count == 2,
              let keyCode = UInt32(parts[0]),
              let modifiers = UInt32(parts[1]) else { return nil }
        let spec = HotKeySpec(keyCode: keyCode, modifiers: modifiers)
        guard spec.isValid else { return nil }
        self = spec
    }

    nonisolated static func keyName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Grave: return "`"
        case kVK_Space: return "空格"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default: return "键码 \(keyCode)"
        }
    }
}

/// 全局快捷键的槽位。rawValue 直接作为 Carbon 的 hot key id，新增槽位不能复用旧值。
nonisolated enum HotKeySlot: UInt32, CaseIterable, Identifiable {
    case toggle = 1
    case presentation = 2

    var id: UInt32 { rawValue }

    var title: String {
        switch self {
        case .toggle: return "开关特效"
        case .presentation: return "演示模式"
        }
    }
}
