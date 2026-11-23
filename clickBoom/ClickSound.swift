import AVFoundation
import Foundation

/// 三种内置点击音色。波形在运行时合成，不占包体，也不需要额外的资源目录。
nonisolated enum ClickSoundStyle: String, CaseIterable, Identifiable, Codable {
    case click
    case soft
    case wood

    var id: String { rawValue }

    var title: String {
        switch self {
        case .click: return "清脆"
        case .soft: return "柔和"
        case .wood: return "木质"
        }
    }

    var detail: String {
        switch self {
        case .click: return "短促的高频点击，适合操作演示"
        case .soft: return "闷一点的低频轻点，长时间听不吵"
        case .wood: return "带木鱼感的双击，节奏感明显"
        }
    }
}

/// 音效的纯规则：音量曲线与节流。抽出来才能不启动音频引擎就测。
enum ClickSoundLogic {
    /// 双击、连点间隔小于 30ms 时只响一次，避免叠成爆音。
    nonisolated static let debounceInterval: TimeInterval = 0.03
    nonisolated static let defaultVolume: Double = 0.35

    /// 人耳感知接近对数，滑块线性值要压一下；0 和 1 两个端点严格保持。
    nonisolated static func gain(volume: Double) -> Float {
        let clamped = min(1, max(0, volume))
        let mapped = log1p(9 * clamped) / log(10)
        return Float(mapped)
    }

    nonisolated static func shouldPlay(
        isEnabled: Bool,
        isRunning: Bool,
        secondsSinceLastPlay: TimeInterval,
        debounce: TimeInterval = debounceInterval
    ) -> Bool {
        guard isEnabled, isRunning else { return false }
        return secondsSinceLastPlay >= debounce
    }
}

/// 音频输出。AVAudioEngine 第一次播放前先预热，避免第一声因为建音频图而延迟。
@MainActor
final class ClickSoundEngine {
    static let shared = ClickSoundEngine()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
    private var buffers: [ClickSoundStyle: AVAudioPCMBuffer] = [:]
    private var lastPlayedAt = Date.distantPast
    private var isConfigured = false

    private init() {}

    func play(style: ClickSoundStyle, volume: Double) {
        let state = AppState.shared
        let now = Date()
        guard ClickSoundLogic.shouldPlay(
            isEnabled: state.clickSoundEnabled,
            isRunning: state.isEnabled && !state.isPaused,
            secondsSinceLastPlay: now.timeIntervalSince(lastPlayedAt)
        ) else { return }
        lastPlayedAt = now

        guard configureIfNeeded(), let buffer = buffers[style] else { return }
        if !engine.isRunning {
            try? engine.start()
        }
        player.volume = ClickSoundLogic.gain(volume: volume)
        player.scheduleBuffer(buffer, at: nil, options: [.interrupts], completionHandler: nil)
        player.play()
    }

    /// 首次播放前建图、装载三种波形并空跑一次，让第一声也立刻响。
    private func configureIfNeeded() -> Bool {
        if isConfigured { return true }
        guard let format else { return false }

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        for style in ClickSoundStyle.allCases {
            if let buffer = Self.makeBuffer(style: style, format: format) {
                buffers[style] = buffer
            }
        }
        guard buffers.count == ClickSoundStyle.allCases.count else { return false }

        do {
            try engine.start()
        } catch {
            return false
        }
        isConfigured = true

        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.rebuildAfterConfigurationChange()
            }
        }
        return true
    }

    /// 换输出设备会打断渲染图（系统音频变化），重建一次，否则之后都静音。
    private func rebuildAfterConfigurationChange() {
        isConfigured = false
        buffers.removeAll()
        player.stop()
        engine.stop()
        if isConfigured == false {
            _ = configureIfNeeded()
        }
    }

    /// 合成一段短音：几个正弦分量 + 少量噪声，指数衰减包络，峰值 −6 dBFS。
    private static func makeBuffer(
        style: ClickSoundStyle,
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let duration: Double
        let partials: [(frequency: Double, amplitude: Double)]
        let noise: Double
        let attack: Double
        let decay: Double

        switch style {
        case .click:
            duration = 0.06
            partials = [(1_250, 1.0), (2_500, 0.35)]
            noise = 0.25
            attack = 0.0015
            decay = 0.018
        case .soft:
            duration = 0.11
            partials = [(760, 1.0), (1_140, 0.22)]
            noise = 0.05
            attack = 0.006
            decay = 0.045
        case .wood:
            duration = 0.13
            partials = [(320, 1.0), (640, 0.5), (960, 0.18)]
            noise = 0.14
            attack = 0.002
            decay = 0.032
        }

        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0] else {
            return nil
        }
        buffer.frameLength = frameCount

        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func nextNoise() -> Double {
            seed ^= seed << 13
            seed ^= seed >> 7
            seed ^= seed << 17
            return Double(seed % 10_000) / 5_000.0 - 1.0
        }

        let peak = 0.5 // −6 dBFS
        var maxValue = 0.0
        for index in 0..<Int(frameCount) {
            let time = Double(index) / sampleRate
            let envelope = (time < attack ? time / attack : exp(-(time - attack) / decay))
            var sample = 0.0
            for partial in partials {
                sample += partial.amplitude * sin(2 * .pi * partial.frequency * time)
            }
            sample += noise * nextNoise()
            sample *= envelope
            channel[index] = Float(sample)
            maxValue = max(maxValue, abs(sample))
        }

        let scale = maxValue > 0 ? Float(peak / maxValue) : 1
        for index in 0..<Int(frameCount) {
            channel[index] *= scale
        }
        return buffer
    }
}
