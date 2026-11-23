import AppKit
import Carbon
import Foundation

/// 一次按键的展示内容：修饰键符号 + 主键。
nonisolated struct KeystrokeEvent: Equatable {
    var keyLabel: String
    var modifiers: String
    var isModifierOnly: Bool
    var isSecureInput: Bool

    nonisolated init(keyLabel: String, modifiers: String, isModifierOnly: Bool, isSecureInput: Bool = false) {
        self.keyLabel = keyLabel
        self.modifiers = modifiers
        self.isModifierOnly = isModifierOnly
        self.isSecureInput = isSecureInput
    }

    /// 完整文案，例如「⌃⌥P」；只按修饰键时只有符号。
    nonisolated var text: String { modifiers + keyLabel }
}

/// 键盘 HUD 的格式化规则：哪张物理键对应哪个字符、组合怎么排、什么时候不该显示。
enum KeystrokeFormatting {
    /// 一行最多 3 个键帽，超出就换行（再超出丢最早的）。
    nonisolated static let maxChipsPerRow = 3

    nonisolated static func modifierSymbols(
        control: Bool,
        option: Bool,
        shift: Bool,
        command: Bool,
        function: Bool = false
    ) -> String {
        var text = ""
        if control { text += "⌃" }
        if option { text += "⌥" }
        if shift { text += "⇧" }
        if command { text += "⌘" }
        if function { text += "fn" }
        return text
    }

    /// 主键标签：优先用当前键盘布局实际打出来的字符，控制字符回退到固定表。
    nonisolated static func keyLabel(keyCode: UInt32, characters: String?) -> String {
        if let characters, !characters.isEmpty {
            let trimmed = characters.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                // 空格键：characters 就是一个空格，trim 后为空，单独给个名字
                return "空格"
            }
            if let first = trimmed.first,
               !first.isNewline,
               first.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F }) {
                return String(first).uppercased()
            }
        }
        return HotKeySpec.keyName(for: keyCode)
    }

    /// 修饰键的键码：这类事件只更新「当前按住什么」，不产生独立键帽。
    nonisolated static func isModifierKeyCode(_ keyCode: UInt32) -> Bool {
        switch Int(keyCode) {
        case kVK_Command, kVK_RightCommand, kVK_Shift, kVK_RightShift,
             kVK_Option, kVK_RightOption, kVK_Control, kVK_RightControl,
             kVK_Function, kVK_CapsLock:
            return true
        default:
            return false
        }
    }

    /// 只显示快捷键时，普通字母键（没有 ⌃⌥⌘）不进 HUD。
    nonisolated static func shouldDisplay(
        modifiers: String,
        showShortcutsOnly: Bool
    ) -> Bool {
        guard showShortcutsOnly else { return true }
        return !modifiers.isEmpty
    }

    /// 安全输入（密码框）期间一律不显示，也不缓存。
    nonisolated static func shouldDisplay(isSecureInput: Bool) -> Bool {
        !isSecureInput
    }
}

/// 键盘 HUD 的尺寸档位：只影响键帽字号与间距。
nonisolated enum KeystrokeHUDSize: Int, CaseIterable, Identifiable {
    case small = 0
    case medium = 1
    case large = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .small: return "小"
        case .medium: return "中"
        case .large: return "大"
        }
    }

    /// 以 15pt 键帽为基准的缩放。
    var scale: CGFloat {
        switch self {
        case .small: return 0.8
        case .medium: return 1.0
        case .large: return 1.3
        }
    }
}
