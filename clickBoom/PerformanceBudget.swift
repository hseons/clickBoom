import Combine
import Foundation

// MARK: - 预算档位

/// 特效绘制的预算档位。默认 `.full` 与 1.9 的视觉上限完全一致；
/// 只有在连续多帧测到绘制超出当前刷新预算时才逐级下调，压力消失后再逐级恢复。
nonisolated enum EffectPerformanceTier: Int, CaseIterable, Comparable, Sendable {
    /// 默认画质：600 粒子 / 180 轨迹点 / 60 fps
    case full = 0
    /// 轻度降级：降低同屏元素上限，刷新率不变
    case balanced = 1
    /// 兜底档：进一步收紧元素，并把覆盖层动画降到 45 fps
    case economy = 2

    static func < (lhs: EffectPerformanceTier, rhs: EffectPerformanceTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// 同屏粒子上限，与点击、预览和连点叠加共用。
    var particleLimit: Int {
        switch self {
        case .full: return 600
        case .balanced: return 360
        case .economy: return 220
        }
    }

    /// 拖尾采样点上限；平滑后每帧的绘制段数大约是它的 2–3 倍。
    var trailPointLimit: Int {
        switch self {
        case .full: return 180
        case .balanced: return 120
        case .economy: return 80
        }
    }

    /// 覆盖层动画的最小刷新间隔。只在兜底档降低，避免默认使用中看到帧率变化。
    var frameInterval: TimeInterval {
        switch self {
        case .full, .balanced: return 1.0 / 60.0
        case .economy: return 1.0 / 45.0
        }
    }

    var title: String {
        switch self {
        case .full: return "完整画质"
        case .balanced: return "平衡"
        case .economy: return "节能"
        }
    }

    /// 段内平均 90% 分位超过这个耗时，说明留给合成与系统的余量不足。
    var degradeThresholdMillis: Double { frameInterval * 1000 * 0.62 }

    /// 回到这一档时要求的分位耗时，比降级阈值更低，形成回差避免来回抖动。
    var recoverThresholdMillis: Double { frameInterval * 1000 * 0.33 }

    var lower: EffectPerformanceTier? { EffectPerformanceTier(rawValue: rawValue + 1) }
    var higher: EffectPerformanceTier? { EffectPerformanceTier(rawValue: rawValue - 1) }
}

// MARK: - 决策规则

nonisolated struct PerformanceBudgetRules: Equatable, Sendable {
    /// 参与分位统计的帧数（60 fps 下约 1 秒）
    var windowSize: Int = 60
    /// 至少攒满一个窗口才判断，避免启动、单次预览或一两帧卡顿就降级
    var minimumSamples: Int = 60
    /// 每多少帧做一次分位计算，降低统计本身的开销
    var evaluationStride: Int = 8
    /// 使用 90% 分位而不是平均值：偶发长帧不放大，持续压力才降级
    var percentile: Double = 0.9
    var changeCooldown: TimeInterval = 1.5
    /// 低于恢复阈值需要持续这么久才升一档
    var recoverHold: TimeInterval = 3.0
    /// 升级后这么快又降级，视为升级失败
    var upgradeFailureWindow: TimeInterval = 6.0
    /// 升级失败后暂停自动升级的时长，防止在临界负载上反复切换
    var upgradeBlockDuration: TimeInterval = 18.0
    /// 实际帧间隔超过这个倍数就记一次卡帧，仅用于诊断
    var stallFactor: Double = 1.75
}

// MARK: - 决策器

/// 纯逻辑的预算决策器：喂入每帧绘制耗时，输出档位变化。
/// 不依赖 SwiftUI 与时钟，测试里可以直接构造任意时间线。
nonisolated struct PerformanceBudgetDecider: Sendable {
    struct Change: Equatable, Sendable {
        let from: EffectPerformanceTier
        let to: EffectPerformanceTier
    }

    struct Snapshot: Equatable, Sendable {
        var tier: EffectPerformanceTier = .full
        /// 当前窗口内的帧数；为 0 表示最近没有活动动画
        var liveSampleCount: Int = 0
        var liveP90Millis: Double?
        /// 最近一次窗口统计的结果，动画结束后仍保留给诊断面板
        var lastP90Millis: Double?
        var lastMeasuredAt: TimeInterval?
        /// 帧间隔明显超过刷新预算的比例，仅作诊断
        var stallRatio: Double = 0
        /// 当前档位是否已经低于默认画质
        var isDegraded: Bool { tier != .full }
    }

    private(set) var tier: EffectPerformanceTier
    let rules: PerformanceBudgetRules

    private var samples: [Double] = []
    private var intervalSamples: [Double] = []
    private var frameCount = 0
    private var lastP90Millis: Double?
    private var lastMeasuredAt: TimeInterval?
    private var lastChangeAt: TimeInterval = -.greatestFiniteMagnitude
    private var lastUpgradeAt: TimeInterval = -.greatestFiniteMagnitude
    private var goodSince: TimeInterval?
    private var upgradeBlockedUntil: TimeInterval = -.greatestFiniteMagnitude

    init(tier: EffectPerformanceTier = .full, rules: PerformanceBudgetRules = PerformanceBudgetRules()) {
        self.tier = tier
        self.rules = rules
        samples.reserveCapacity(rules.windowSize)
        intervalSamples.reserveCapacity(rules.windowSize)
    }

    /// 记录一帧。`adaptive` 为 false 时只统计不决策，用于固定档位的 A/B 测量。
    mutating func record(
        drawMillis: Double,
        intervalMillis: Double? = nil,
        at time: TimeInterval,
        adaptive: Bool = true
    ) -> Change? {
        guard drawMillis.isFinite, drawMillis >= 0 else { return nil }

        samples.append(drawMillis)
        if samples.count > rules.windowSize {
            samples.removeFirst(samples.count - rules.windowSize)
        }
        if let intervalMillis, intervalMillis.isFinite, intervalMillis > 0 {
            intervalSamples.append(intervalMillis)
            if intervalSamples.count > rules.windowSize {
                intervalSamples.removeFirst(intervalSamples.count - rules.windowSize)
            }
        }
        frameCount += 1

        guard samples.count >= rules.minimumSamples else { return nil }
        guard frameCount % rules.evaluationStride == 0 else { return nil }

        guard let p90 = Self.percentile(samples, rules.percentile) else { return nil }
        lastP90Millis = p90
        lastMeasuredAt = time
        guard adaptive else { return nil }

        if tier < .economy, p90 > tier.degradeThresholdMillis,
           time - lastChangeAt >= rules.changeCooldown {
            let from = tier
            tier = tier.lower ?? tier
            if time - lastUpgradeAt <= rules.upgradeFailureWindow {
                // 刚升上去又被打回：这段时间不再尝试升级
                upgradeBlockedUntil = max(upgradeBlockedUntil, time + rules.upgradeBlockDuration)
            }
            clearMeasurement()
            lastChangeAt = time
            goodSince = nil
            return Change(from: from, to: tier)
        }

        guard let target = tier.higher, p90 < target.recoverThresholdMillis,
              time >= upgradeBlockedUntil,
              time - lastChangeAt >= rules.changeCooldown else {
            goodSince = nil
            return nil
        }

        if goodSince == nil { goodSince = time }
        guard let since = goodSince, time - since >= rules.recoverHold else { return nil }

        let from = tier
        tier = target
        lastUpgradeAt = time
        lastChangeAt = time
        goodSince = nil
        clearMeasurement()
        return Change(from: from, to: tier)
    }

    /// 清空当前窗口但保留最后一次统计结果；特效结束后调用，下一次动画从默认画质开始。
    mutating func restart(at time: TimeInterval) {
        tier = .full
        clearMeasurement()
        lastChangeAt = time - rules.changeCooldown
        lastUpgradeAt = -.greatestFiniteMagnitude
        upgradeBlockedUntil = -.greatestFiniteMagnitude
        goodSince = nil
    }

    /// 固定档位时不参与决策，只保证外部读到正确档位。
    mutating func pin(to pinned: EffectPerformanceTier, at time: TimeInterval) {
        tier = pinned
        clearMeasurement()
        lastChangeAt = time
        goodSince = nil
    }

    func snapshot() -> Snapshot {
        let stallThreshold = tier.frameInterval * 1000 * rules.stallFactor
        let stalls = intervalSamples.reduce(into: 0) { count, interval in
            if interval > stallThreshold { count += 1 }
        }
        return Snapshot(
            tier: tier,
            liveSampleCount: samples.count,
            liveP90Millis: Self.percentile(samples, rules.percentile),
            lastP90Millis: lastP90Millis,
            lastMeasuredAt: lastMeasuredAt,
            stallRatio: intervalSamples.isEmpty ? 0 : Double(stalls) / Double(intervalSamples.count)
        )
    }

    private mutating func clearMeasurement() {
        samples.removeAll(keepingCapacity: true)
        intervalSamples.removeAll(keepingCapacity: true)
        frameCount = 0
    }

    static func percentile(_ values: [Double], _ percentile: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let clamped = min(max(percentile, 0), 1)
        let rank = Int((clamped * Double(sorted.count)).rounded(.up)) - 1
        return sorted[min(max(rank, 0), sorted.count - 1)]
    }
}

// MARK: - 线程安全的采样入口

/// 覆盖层的 Canvas 渲染可能不在主线程，采样和决策都放在锁内完成；
/// 档位变化很少发生，只在变化时切回主线程通知 App。
nonisolated final class FrameCostProbe: @unchecked Sendable {
    static let shared = FrameCostProbe()

    private let lock = NSLock()
    private var decider: PerformanceBudgetDecider
    private var lastRecordAt: TimeInterval?
    private var changeHandler: (@Sendable (EffectPerformanceTier) -> Void)?
    /// 环境变量固定的档位；不为 nil 时不自动升降级，只做统计
    let pinnedTier: EffectPerformanceTier?

    init(
        pinnedTier: EffectPerformanceTier? = FrameCostProbe.pinnedTierFromEnvironment(),
        rules: PerformanceBudgetRules = PerformanceBudgetRules()
    ) {
        self.pinnedTier = pinnedTier
        self.decider = PerformanceBudgetDecider(tier: pinnedTier ?? .full, rules: rules)
    }

    var isPinned: Bool { pinnedTier != nil }

    func setTierChangeHandler(_ handler: (@Sendable (EffectPerformanceTier) -> Void)?) {
        lock.lock()
        defer { lock.unlock() }
        changeHandler = handler
    }

    /// 由覆盖层在每帧绘制结束时调用；`drawSeconds` 只覆盖 Canvas 绘制本身。
    func record(drawSeconds: Double, at time: TimeInterval) {
        var change: PerformanceBudgetDecider.Change?
        var handler: (@Sendable (EffectPerformanceTier) -> Void)?

        lock.lock()
        let interval = lastRecordAt.map { time - $0 }
        lastRecordAt = time
        // 暂停后重新开始的第一个间隔可能是任意长，不作为卡帧证据
        let usableInterval: Double?
        if let interval, interval > 0, interval < 2 { usableInterval = interval * 1000 } else { usableInterval = nil }
        change = decider.record(
            drawMillis: max(0, drawSeconds) * 1000,
            intervalMillis: usableInterval,
            at: time,
            adaptive: pinnedTier == nil
        )
        handler = changeHandler
        lock.unlock()

        if let change, let handler {
            handler(change.to)
        }
    }

    func snapshot() -> PerformanceBudgetDecider.Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return decider.snapshot()
    }

    /// 特效全部结束、进入静默或切换空间时调用。
    func restart() {
        lock.lock()
        defer { lock.unlock() }
        let now = ProcessInfo.processInfo.systemUptime
        lastRecordAt = nil
        if let pinnedTier {
            decider.pin(to: pinnedTier, at: now)
        } else {
            decider.restart(at: now)
        }
    }

    private static func pinnedTierFromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> EffectPerformanceTier? {
        guard let raw = environment["CLICKBOOM_EFFECT_TIER"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        switch raw.lowercased() {
        case "full", "off", "0": return .full
        case "balanced", "1": return .balanced
        case "economy", "minimal", "conservative", "2": return .economy
        default: return nil
        }
    }
}

// MARK: - 主线程镜像

/// 引擎和覆盖层在主线程读取的预算镜像。档位变化后立刻裁剪元素并调整刷新间隔。
@MainActor
final class EffectBudgetStore: ObservableObject {
    static let shared = EffectBudgetStore()

    @Published private(set) var tier: EffectPerformanceTier
    let probe: FrameCostProbe

    init(probe: FrameCostProbe = .shared) {
        self.probe = probe
        self.tier = probe.snapshot().tier
        probe.setTierChangeHandler { [weak self] tier in
            Task { @MainActor [weak self] in
                self?.applyAdaptiveTier(tier)
            }
        }
    }

    var isPinned: Bool { probe.isPinned }

    /// 诊断面板读取的即时快照，不改动 @Published，避免在渲染中触发更新。
    var currentSnapshot: PerformanceBudgetDecider.Snapshot { probe.snapshot() }

    private func applyAdaptiveTier(_ newTier: EffectPerformanceTier) {
        guard newTier != tier else { return }
        tier = newTier
    }

    /// 特效全部结束或进入静默：回到默认画质，下一段动画从头测量。
    func restartIfIdle() {
        let snapshot = probe.snapshot()
        guard snapshot.liveSampleCount > 0 || tier != .full else { return }
        probe.restart()
        if tier != .full { tier = .full }
    }
}
