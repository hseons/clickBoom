import AppKit
import XCTest
@testable import ClickBoom

final class PerformanceBudgetTests: XCTestCase {
    /// 以 60 fps 的时间线连续喂帧，返回期间发生的档位变化。
    private func feed(
        _ decider: inout PerformanceBudgetDecider,
        frames: Int,
        drawMillis: Double,
        intervalMillis: Double = 1000.0 / 60.0,
        from start: Double,
        adaptive: Bool = true
    ) -> [PerformanceBudgetDecider.Change] {
        var changes: [PerformanceBudgetDecider.Change] = []
        for index in 0..<frames {
            let time = start + Double(index) / 60.0
            if let change = decider.record(
                drawMillis: drawMillis,
                intervalMillis: intervalMillis,
                at: time,
                adaptive: adaptive
            ) {
                changes.append(change)
            }
        }
        return changes
    }

    func testTierLimitsTightenMonotonically() {
        XCTAssertGreaterThan(EffectPerformanceTier.full.particleLimit, EffectPerformanceTier.balanced.particleLimit)
        XCTAssertGreaterThan(EffectPerformanceTier.balanced.particleLimit, EffectPerformanceTier.economy.particleLimit)
        XCTAssertGreaterThan(EffectPerformanceTier.full.trailPointLimit, EffectPerformanceTier.balanced.trailPointLimit)
        XCTAssertGreaterThan(EffectPerformanceTier.balanced.trailPointLimit, EffectPerformanceTier.economy.trailPointLimit)
        XCTAssertEqual(EffectPerformanceTier.full.particleLimit, 600)
        XCTAssertEqual(EffectPerformanceTier.full.trailPointLimit, 180)
        XCTAssertEqual(EffectPerformanceTier.full.frameInterval, 1.0 / 60.0)
        XCTAssertGreaterThan(EffectPerformanceTier.economy.frameInterval, EffectPerformanceTier.full.frameInterval)
        XCTAssertLessThan(EffectPerformanceTier.full, EffectPerformanceTier.economy)
    }

    func testFullWindowOfFastFramesKeepsFullQuality() {
        var decider = PerformanceBudgetDecider()
        let changes = feed(&decider, frames: 600, drawMillis: 3, from: 0)
        XCTAssertTrue(changes.isEmpty)
        XCTAssertEqual(decider.tier, .full)
        XCTAssertEqual(decider.snapshot().liveP90Millis ?? 0, 3, accuracy: 0.001)
    }

    func testSustainedOverBudgetDegradesOneTierAtATime() {
        var decider = PerformanceBudgetDecider()
        let first = feed(&decider, frames: 64, drawMillis: 14, from: 0)
        XCTAssertEqual(first.count, 1, "一个窗口只降一档")
        XCTAssertEqual(first.first?.from, .full)
        XCTAssertEqual(first.first?.to, .balanced)

        let second = feed(&decider, frames: 200, drawMillis: 14, from: 64.0 / 60.0)
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second.first?.from, .balanced)
        XCTAssertEqual(second.first?.to, .economy)
        XCTAssertEqual(decider.tier, .economy)
    }

    func testCooldownPreventsImmediateSecondChange() {
        var decider = PerformanceBudgetDecider()
        let first = feed(&decider, frames: 64, drawMillis: 14, from: 0)
        XCTAssertEqual(first.count, 1)

        // 变化后 1.5 秒内即使仍有压力也不再降级
        let withinCooldown = feed(&decider, frames: 70, drawMillis: 14, from: 64.0 / 60.0)
        XCTAssertTrue(withinCooldown.isEmpty)
        XCTAssertEqual(decider.tier, .balanced)

        // 冷却结束后继续超预算，再降一档
        let afterCooldown = feed(&decider, frames: 60, drawMillis: 14, from: 134.0 / 60.0)
        XCTAssertEqual(afterCooldown.map(\.to), [.economy])
    }

    func testShortHitchDoesNotDegrade() {
        var decider = PerformanceBudgetDecider()
        _ = feed(&decider, frames: 8, drawMillis: 40, from: 0)
        let changes = feed(&decider, frames: 300, drawMillis: 4, from: 8.0 / 60.0)
        XCTAssertTrue(changes.isEmpty, "10% 以内的偶发长帧应由分位数吸收")
        XCTAssertEqual(decider.tier, .full)
    }

    func testEconomyIsTheFloorEvenUnderExtremeLoad() {
        var decider = PerformanceBudgetDecider(tier: .economy)
        let changes = feed(&decider, frames: 600, drawMillis: 40, from: 0)
        XCTAssertTrue(changes.isEmpty)
        XCTAssertEqual(decider.tier, .economy)
    }

    func testRecoveryNeedsSustainedHeadroomAndStepsUpOneTier() {
        var decider = PerformanceBudgetDecider(tier: .economy)
        let changes = feed(&decider, frames: 600, drawMillis: 5, from: 0)
        XCTAssertEqual(changes.map(\.to), [.balanced, .full])
        XCTAssertEqual(decider.tier, .full)
        XCTAssertNotNil(decider.snapshot().lastP90Millis)
    }

    func testBriefHeadroomDoesNotRecover() {
        var decider = PerformanceBudgetDecider(tier: .economy)
        // 恢复需要 3 秒连续低负载；2.5 秒还不够
        let changes = feed(&decider, frames: 150, drawMillis: 5, from: 0)
        XCTAssertTrue(changes.isEmpty)
        XCTAssertEqual(decider.tier, .economy)
    }

    func testFailedUpgradeTemporarilyBlocksFurtherRecovery() {
        var decider = PerformanceBudgetDecider(tier: .economy)
        _ = feed(&decider, frames: 300, drawMillis: 5, from: 0)
        XCTAssertEqual(decider.tier, .balanced, "第一次恢复升到平衡档")

        // 刚升上去马上又超载：降回兜底档并暂停自动升级
        var time = 300.0 / 60.0
        let downgrade = feed(&decider, frames: 240, drawMillis: 14, from: time)
        XCTAssertEqual(downgrade.map(\.to), [.economy])
        time += 240.0 / 60.0

        // 18 秒封锁期内即使负载很低也不再升级
        let blocked = feed(&decider, frames: 600, drawMillis: 5, from: time)
        XCTAssertTrue(blocked.isEmpty)
        time += 600.0 / 60.0
        XCTAssertEqual(decider.tier, .economy)

        // 封锁期过后恢复正常升级，且仍按档逐级恢复
        let recovered = feed(&decider, frames: 900, drawMillis: 5, from: time)
        XCTAssertEqual(recovered.first?.to, .balanced)
        XCTAssertEqual(decider.tier, .full)
    }

    func testRestartClearsWindowAndReturnsToFullQuality() {
        var decider = PerformanceBudgetDecider()
        _ = feed(&decider, frames: 100, drawMillis: 14, from: 0)
        XCTAssertEqual(decider.tier, .balanced)
        XCTAssertNotNil(decider.snapshot().lastP90Millis)

        decider.restart(at: 2)
        XCTAssertEqual(decider.tier, .full)
        XCTAssertEqual(decider.snapshot().liveSampleCount, 0)
        XCTAssertNotNil(decider.snapshot().lastP90Millis, "最近一次统计保留给诊断面板")

        // 重新开始后先按默认画质累计一个完整窗口，不沿用旧样本
        let changes = feed(&decider, frames: 60, drawMillis: 3, from: 2)
        XCTAssertTrue(changes.isEmpty)
        XCTAssertEqual(decider.tier, .full)
    }

    func testNonAdaptiveRecordingOnlyCollectsMetrics() {
        var decider = PerformanceBudgetDecider()
        let changes = feed(&decider, frames: 300, drawMillis: 25, from: 0, adaptive: false)
        XCTAssertTrue(changes.isEmpty, "固定档位时只统计不降级")
        XCTAssertEqual(decider.tier, .full)
        XCTAssertEqual(decider.snapshot().lastP90Millis ?? 0, 25, accuracy: 0.001)
    }

    func testSnapshotReportsStallRatio() {
        var decider = PerformanceBudgetDecider()
        _ = feed(&decider, frames: 70, drawMillis: 3, intervalMillis: 40, from: 0, adaptive: false)
        XCTAssertGreaterThan(decider.snapshot().stallRatio, 0.9)
    }

    func testPinnedProbeKeepsTierWhileMeasuring() {
        let probe = FrameCostProbe(pinnedTier: .balanced)
        XCTAssertTrue(probe.isPinned)
        for index in 0..<400 {
            probe.record(drawSeconds: 0.03, at: Double(index) / 60.0)
        }
        let snapshot = probe.snapshot()
        XCTAssertEqual(snapshot.tier, .balanced)
        XCTAssertNotNil(snapshot.lastP90Millis)
    }

    func testProbeRestartReturnsToFullTier() {
        let probe = FrameCostProbe(pinnedTier: nil)
        for index in 0..<400 {
            probe.record(drawSeconds: 0.02, at: Double(index) / 60.0)
        }
        XCTAssertNotEqual(probe.snapshot().tier, .full)
        probe.restart()
        XCTAssertEqual(probe.snapshot().tier, .full)
        XCTAssertEqual(probe.snapshot().liveSampleCount, 0)
    }

    @MainActor
    func testBudgetStoreFollowsProbeMeasurements() async {
        let probe = FrameCostProbe(pinnedTier: nil)
        let store = EffectBudgetStore(probe: probe)
        XCTAssertEqual(store.tier, .full)

        for index in 0..<80 {
            probe.record(drawSeconds: 0.02, at: Double(index) / 60.0)
        }
        // 探针回调经由主线程任务落到 store
        for _ in 0..<50 {
            await Task.yield()
        }
        XCTAssertEqual(store.tier, .balanced)
        XCTAssertFalse(store.isPinned)
        XCTAssertEqual(store.currentSnapshot.liveP90Millis ?? 0, 20, accuracy: 0.001)
    }

    @MainActor
    func testEngineAdoptsTierFromLiveMeasurements() async {
        let suite = "ClickBoomTests.BudgetLive.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = AppState(defaults: defaults)
        state.particleCount = 32
        let probe = FrameCostProbe(pinnedTier: nil)
        let store = EffectBudgetStore(probe: probe)
        let engine = EffectEngine(state: state, budgetStore: store)
        for _ in 0..<25 {
            engine.trigger(at: CGPoint(x: 5, y: 5))
        }
        XCTAssertEqual(engine.particles.count, EffectPerformanceTier.full.particleLimit)

        // 连续 80 帧超出 60 fps 的绘制预算：探针判定后经主线程落到引擎
        for index in 0..<80 {
            probe.record(drawSeconds: 0.02, at: Double(index) / 60.0)
        }
        for _ in 0..<50 {
            await Task.yield()
        }
        XCTAssertEqual(store.tier, .balanced)
        XCTAssertEqual(engine.particles.count, EffectPerformanceTier.balanced.particleLimit)
    }

    @MainActor
    func testEngineTrimsExistingParticlesWhenBudgetDrops() {
        let suite = "ClickBoomTests.Budget.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = AppState(defaults: defaults)
        state.particleCount = 32
        let engine = EffectEngine(state: state)
        for _ in 0..<25 {
            engine.trigger(at: CGPoint(x: 10, y: 20))
        }
        XCTAssertEqual(engine.particles.count, EffectPerformanceTier.full.particleLimit)

        engine.applyBudget(.economy)
        XCTAssertEqual(engine.particles.count, EffectPerformanceTier.economy.particleLimit)

        // 恢复档位不会凭空补回粒子
        engine.applyBudget(.full)
        XCTAssertEqual(engine.particles.count, EffectPerformanceTier.economy.particleLimit)
    }
}
