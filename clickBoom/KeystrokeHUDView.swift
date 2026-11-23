import AppKit
import Combine
import SwiftUI

/// 一个键帽。
nonisolated struct KeystrokeChip: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var createdAt: Date
}

/// 一行键帽，最多 3 个。
nonisolated struct KeystrokeChipRow: Identifiable, Equatable {
    let id = UUID()
    var chips: [KeystrokeChip]
}

/// HUD 里正在显示的内容与过期清理。
@MainActor
final class KeystrokeHUDModel: ObservableObject {
    @Published private(set) var rows: [KeystrokeChipRow] = []

    /// 一个键帽停留多久后淡出。
    static let chipLifetime: TimeInterval = 1.6
    /// 保留几行历史，设置里可选 1–3。
    var maxRows = 2

    func push(_ text: String, at date: Date = Date()) {
        guard !text.isEmpty else { return }
        prune(now: date)

        if let index = rows.indices.last, rows[index].chips.count < KeystrokeFormatting.maxChipsPerRow {
            rows[index].chips.append(KeystrokeChip(text: text, createdAt: date))
        } else {
            rows.append(KeystrokeChipRow(chips: [KeystrokeChip(text: text, createdAt: date)]))
        }
        while rows.count > max(1, maxRows) {
            rows.removeFirst()
        }
    }

    func prune(now: Date = Date()) {
        let updated = rows.compactMap { row -> KeystrokeChipRow? in
            let chips = row.chips.filter { now.timeIntervalSince($0.createdAt) < Self.chipLifetime }
            return chips.isEmpty ? nil : KeystrokeChipRow(chips: chips)
        }
        if updated != rows {
            rows = updated
        }
    }

    func clear() {
        if !rows.isEmpty { rows = [] }
    }

    var isEmpty: Bool { rows.isEmpty }
}

/// 键帽外观。尺寸用档位乘一个基准，避免三套硬编码排版。
struct KeystrokeHUDView: View {
    @ObservedObject var model: KeystrokeHUDModel
    var scale: CGFloat

    var body: some View {
        VStack(alignment: .center, spacing: 6 * scale) {
            ForEach(model.rows) { row in
                HStack(spacing: 6 * scale) {
                    ForEach(row.chips) { chip in
                        Text(chip.text)
                            .font(.system(size: 15 * scale, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9 * scale)
                            .padding(.vertical, 5 * scale)
                            .background(
                                RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
                                    .fill(Color.black.opacity(0.55))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.35), radius: 4 * scale, y: 1)
                    }
                }
            }
        }
        .padding(.horizontal, 10 * scale)
        .padding(.vertical, 8 * scale)
        .background(
            RoundedRectangle(cornerRadius: 14 * scale, style: .continuous)
                .fill(Color.black.opacity(0.28))
        )
        .fixedSize()
        .allowsHitTesting(false)
    }
}

/// 独立的键盘 HUD 面板：不抢焦点、不接收鼠标、跟着指针所在的屏幕走。
@MainActor
final class KeystrokeHUDController: ObservableObject {
    static let shared = KeystrokeHUDController()

    /// 已授权但事件监听起不来：一般是系统要求重启进程才生效。
    @Published private(set) var needsRelaunch = false

    let model = KeystrokeHUDModel()
    private var panel: NSPanel?
    private var monitor: KeystrokeMonitor?
    private var pruneTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private var started = false
    private var lastScale: CGFloat = 1

    func start() {
        guard !started else { return }
        started = true

        let state = AppState.shared
        monitor = KeystrokeMonitor.shared
        monitor?.onEvent = { [weak self] event in
            self?.handle(event)
        }
        monitor?.onClear = { [weak self] in
            self?.model.clear()
            self?.hideIfEmpty()
        }

        Publishers.MergeMany([
            state.$keystrokeHUDEnabled.map { _ in () }.eraseToAnyPublisher(),
            state.$keystrokeHUDSizeRaw.map { _ in () }.eraseToAnyPublisher(),
            state.$keystrokeHUDLineCount.map { _ in () }.eraseToAnyPublisher(),
            state.$keystrokeHUDShowShortcutsOnly.map { _ in () }.eraseToAnyPublisher(),
            state.$appRules.map { _ in () }.eraseToAnyPublisher(),
            InputPermission.shared.$isGranted.map { _ in () }.eraseToAnyPublisher(),
            RuntimeController.shared.$status.map { _ in () }.eraseToAnyPublisher(),
            RuntimeController.shared.$targetApp.map { _ in () }.eraseToAnyPublisher()
        ])
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.sync() }
        .store(in: &cancellables)

        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.model.prune()
                self.hideIfEmpty()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pruneTimer = timer

        sync()
    }

    func stop() {
        started = false
        cancellables.removeAll()
        pruneTimer?.invalidate()
        pruneTimer = nil
        monitor?.stop()
        model.clear()
        panel?.orderOut(nil)
        panel = nil
    }

    /// 全局开关、权限、应用规则三者都允许时才真正监听。
    private var isAllowed: Bool {
        let state = AppState.shared
        guard state.keystrokeHUDEnabled, InputPermission.shared.isGranted else { return false }
        let status = RuntimeController.shared.status
        if case .excluded = status { return false }
        let frontmost = RuntimeController.shared.targetApp?.bundleID
            ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return AppRuleLogic.isHUDAllowed(
            for: frontmost,
            in: state.appRules,
            globalEnabled: true
        )
    }

    private func sync() {
        guard started else { return }
        guard isAllowed else {
            monitor?.stop()
            needsRelaunch = false
            model.clear()
            hideIfEmpty()
            return
        }
        model.maxRows = AppState.shared.keystrokeHUDLineCount
        guard monitor?.start() == true else {
            needsRelaunch = InputPermission.shared.isGranted
            monitor?.stop()
            return
        }
        needsRelaunch = false
        lastScale = AppState.shared.keystrokeHUDSize.scale
        if !model.isEmpty {
            panel?.contentView?.layoutSubtreeIfNeeded()
            layout()
            panel?.orderFrontRegardless()
        }
    }

    /// 界面上「预览」按钮用：只验证浮层渲染，不依赖权限。
    func preview() {
        let state = AppState.shared
        model.maxRows = max(state.keystrokeHUDLineCount, 1)
        model.push("⌘⇧H")
        showIfNeeded()
    }

    private func handle(_ event: KeystrokeEvent) {
        guard isAllowed else { return }
        let state = AppState.shared
        guard KeystrokeFormatting.shouldDisplay(modifiers: event.modifiers,
                                                showShortcutsOnly: state.keystrokeHUDShowShortcutsOnly) else {
            return
        }
        model.maxRows = state.keystrokeHUDLineCount
        model.push(event.text)
        showIfNeeded()
    }

    private func showIfNeeded() {
        let scale = AppState.shared.keystrokeHUDSize.scale
        if panel == nil || scale != lastScale {
            lastScale = scale
            rebuildPanel(scale: scale)
        }
        layout()
        panel?.orderFrontRegardless()
    }

    private func rebuildPanel(scale: CGFloat) {
        panel?.orderOut(nil)
        let view = KeystrokeHUDView(model: model, scale: scale)
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)
        self.panel = panel
    }

    /// 放在指针所在屏幕的底部居中，不挡内容也不跟着鼠标抖。
    private func layout() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let origin = CGPoint(
            x: visible.midX - size.width / 2,
            y: visible.minY + 96
        )
        panel.setFrameOrigin(origin)
    }

    private func hideIfEmpty() {
        if model.isEmpty {
            panel?.orderOut(nil)
        }
    }
}
