import AppKit
import Combine
import Carbon
import Foundation
import os

/// 键盘事件源。
///
/// 首选 `CGEventTap`（listenOnly，不拦截、不改事件），拿不到就回退到
/// `NSEvent` 全局监听——后者在部分系统上只能收到 keyDown，没有 keyUp，
/// 但配合「按下即显示」的 HUD 逻辑已经够用。
@MainActor
final class KeystrokeMonitor: ObservableObject {
    static let shared = KeystrokeMonitor()

    @Published private(set) var isFallbackActive = false
    /// 连续失败次数；达到 3 次就常驻回退方案，不再反复重试事件 tap。
    @Published private(set) var tapFailureCount = 0

    var onEvent: ((KeystrokeEvent) -> Void)?
    var onClear: (() -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var fallbackMonitor: Any?
    private var isRunning = false

    private static let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        | (1 << CGEventType.keyUp.rawValue)
        | (1 << CGEventType.flagsChanged.rawValue)

    private let log = Logger(subsystem: "mumu.AIGG.clickBoom", category: "keystroke")

    /// 启动监听；返回是否真的挂上了某个事件源。
    ///
    /// 没授权时直接返回 false，不去装 NSEvent 全局监听——那个 API 在未授权时
    /// 仍会返回一个 token，看起来「监听成功」，其实一个事件都收不到。
    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }
        guard CGPreflightListenEventAccess() else {
            log.info("start denied: no input monitoring")
            return false
        }
        isRunning = true
        if installTap() {
            log.info("tap installed")
            return true
        }
        log.error("tap create failed, falling back")
        let ok = installFallback()
        log.info("fallback=\(ok, privacy: .public)")
        return ok
    }

    func stop() {
        isRunning = false
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        if let fallbackMonitor {
            NSEvent.removeMonitor(fallbackMonitor)
        }
        fallbackMonitor = nil
        isFallbackActive = false
    }

    /// 权限刚授予、或系统把 tap 关掉之后重建一次。
    func restart() {
        stop()
        tapFailureCount = 0
        start()
    }

    private func installTap() -> Bool {
        let mask = Self.eventMask
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: keystrokeTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }
        self.tap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isFallbackActive = false
        return true
    }

    private func installFallback() -> Bool {
        let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleFallback(event)
            }
        }
        guard let monitor else { return false }
        fallbackMonitor = monitor
        isFallbackActive = true
        return true
    }

    private func handleFallback(_ event: NSEvent) {
        guard isRunning else { return }
        if event.type == .flagsChanged {
            let symbols = KeystrokeFormatting.modifierSymbols(
                control: event.modifierFlags.contains(.control),
                option: event.modifierFlags.contains(.option),
                shift: event.modifierFlags.contains(.shift),
                command: event.modifierFlags.contains(.command),
                function: event.modifierFlags.contains(.function)
            )
            if !symbols.isEmpty {
                deliver(KeystrokeEvent(keyLabel: "", modifiers: symbols, isModifierOnly: true))
            }
            return
        }
        let modifiers = KeystrokeFormatting.modifierSymbols(
            control: event.modifierFlags.contains(.control),
            option: event.modifierFlags.contains(.option),
            shift: event.modifierFlags.contains(.shift),
            command: event.modifierFlags.contains(.command),
            function: event.modifierFlags.contains(.function)
        )
        let label = KeystrokeFormatting.keyLabel(
            keyCode: UInt32(event.keyCode),
            characters: event.charactersIgnoringModifiers
        )
        deliver(KeystrokeEvent(keyLabel: label, modifiers: modifiers, isModifierOnly: false))
    }

    /// 事件 tap 回调转进来的入口（主线程）。
    func handleTapEvent(
        type: CGEventType,
        keyCode: UInt32,
        flags: CGEventFlags,
        characters: String?
    ) {
        guard isRunning else { return }
        if KeystrokeFormatting.isModifierKeyCode(keyCode) {
            deliverModifiersOnly(flags: flags)
            return
        }
        guard type == .keyDown else { return }
        log.debug("key keyCode=\(keyCode, privacy: .public)")
        let modifiers = KeystrokeFormatting.modifierSymbols(
            control: flags.contains(.maskControl),
            option: flags.contains(.maskAlternate),
            shift: flags.contains(.maskShift),
            command: flags.contains(.maskCommand),
            function: flags.contains(.maskSecondaryFn)
        )
        let label = KeystrokeFormatting.keyLabel(keyCode: keyCode, characters: characters)
        deliver(KeystrokeEvent(keyLabel: label, modifiers: modifiers, isModifierOnly: false))
    }

    private func deliverModifiersOnly(flags: CGEventFlags) {
        let symbols = KeystrokeFormatting.modifierSymbols(
            control: flags.contains(.maskControl),
            option: flags.contains(.maskAlternate),
            shift: flags.contains(.maskShift),
            command: flags.contains(.maskCommand),
            function: flags.contains(.maskSecondaryFn)
        )
        guard !symbols.isEmpty else { return }
        deliver(KeystrokeEvent(keyLabel: "", modifiers: symbols, isModifierOnly: true))
    }

    private func deliver(_ event: KeystrokeEvent) {
        // 密码框：立刻清空 HUD，并暂停一小会儿，避免把输入节奏也暴露出来。
        if IsSecureEventInputEnabled() {
            onClear?()
            return
        }
        onEvent?(event)
    }

    /// tap 被系统禁用（超时 / 用户输入打断）后的恢复。
    func handleTapDisabled() {
        guard isRunning else { return }
        tapFailureCount += 1
        if tapFailureCount >= 3 {
            // 反复被禁：说明 tap 在这台机器上不可靠，常驻回退方案。
            stop()
            isRunning = true
            _ = installFallback()
            return
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }
}

/// C 回调不能捕获上下文，所有状态都从 userInfo 取回主线程再处理。
private nonisolated func keystrokeTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<KeystrokeMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        Task { @MainActor in
            monitor.handleTapDisabled()
        }
        return Unmanaged.passUnretained(event)
    }

    let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
    let flags = event.flags

    var characters: String?
    if type == .keyDown {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &length, unicodeString: &buffer)
        if length > 0 {
            characters = String(utf16CodeUnits: buffer, count: length)
        }
    }

    Task { @MainActor in
        monitor.handleTapEvent(type: type, keyCode: keyCode, flags: flags, characters: characters)
    }
    return Unmanaged.passUnretained(event)
}
