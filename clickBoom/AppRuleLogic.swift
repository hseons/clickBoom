import AppKit
import Foundation

/// 单个 App 的生效规则。
///
/// 「静默」是原来排除列表的能力；这里再加两项最常见的演示需求：
/// 进这个 App 自动套一个预设、以及只关掉拖尾但保留点击特效。
/// 只存预设 id 不复制参数，避免预设改了之后 App 规则还停在旧数值上。
nonisolated struct AppRule: Codable, Identifiable, Hashable {
    var bundleID: String
    var name: String
    /// 在这个 App 里完全不显示点击特效和拖尾
    var silence: Bool
    /// 进入这个 App 自动套用的自定义预设；nil 表示沿用当前设置
    var presetID: UUID?
    /// 只关掉拖尾，点击特效照常
    var disablesTrail: Bool
    /// 键盘 HUD 是否显示；nil 表示跟随全局开关
    var hudEnabled: Bool?

    nonisolated init(
        bundleID: String,
        name: String,
        silence: Bool = false,
        presetID: UUID? = nil,
        disablesTrail: Bool = false,
        hudEnabled: Bool? = nil
    ) {
        self.bundleID = bundleID
        self.name = name
        self.silence = silence
        self.presetID = presetID
        self.disablesTrail = disablesTrail
        self.hudEnabled = hudEnabled
    }

    var id: String { bundleID }
}

/// App 规则的纯逻辑：规范化、增删改、和旧排除列表互转。
enum AppRuleLogic {
    nonisolated static func normalize(_ bundleID: String?) -> String? {
        guard let trimmed = bundleID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// 按前台 App 找规则；找不到就是「没有规则」，由全局开关决定。
    nonisolated static func resolving(bundleID: String?, in rules: [AppRule]) -> AppRule? {
        guard let target = normalize(bundleID) else { return nil }
        return rules.first { normalize($0.bundleID) == target }
    }

    nonisolated static func adding(
        _ rule: AppRule,
        to rules: [AppRule],
        ownBundleID: String? = Bundle.main.bundleIdentifier
    ) -> [AppRule] {
        guard let bundleID = normalize(rule.bundleID),
              bundleID != normalize(ownBundleID) else {
            return rules
        }
        let name = rule.name.trimmingCharacters(in: .whitespacesAndNewlines)
        var normalized = rule
        normalized.bundleID = bundleID
        normalized.name = name.isEmpty ? bundleID : name

        var updated = rules.filter { normalize($0.bundleID) != bundleID }
        updated.append(normalized)
        return updated
    }

    nonisolated static func removing(bundleID: String, from rules: [AppRule]) -> [AppRule] {
        guard let target = normalize(bundleID) else { return rules }
        return rules.filter { normalize($0.bundleID) != target }
    }

    /// 就地把某条规则换成新值；列表里没有就原样返回。
    nonisolated static func updating(_ rule: AppRule, in rules: [AppRule]) -> [AppRule] {
        guard let target = normalize(rule.bundleID) else { return rules }
        guard let index = rules.firstIndex(where: { normalize($0.bundleID) == target }) else {
            return rules
        }
        var updated = rules
        updated[index].silence = rule.silence
        updated[index].presetID = rule.presetID
        updated[index].disablesTrail = rule.disablesTrail
        updated[index].hudEnabled = rule.hudEnabled
        if !rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updated[index].name = rule.name
        }
        return updated
    }

    /// 规则列表 → 旧的排除列表，保留对 RuntimeStatus / 老版本设置的兼容。
    nonisolated static func exclusions(from rules: [AppRule]) -> [ExcludedApp] {
        rules
            .filter(\.silence)
            .map { ExcludedApp(bundleID: $0.bundleID, name: $0.name) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// 旧排除列表 → 规则，升级时把每个被排除的 App 变成「静默」规则。
    nonisolated static func rules(from exclusions: [ExcludedApp]) -> [AppRule] {
        exclusions.map { AppRule(bundleID: $0.bundleID, name: $0.name, silence: true) }
    }

    /// 导入备份：逐条合并，重复的以新导入的为准。
    nonisolated static func merging(
        _ incoming: [AppRule],
        into existing: [AppRule],
        ownBundleID: String? = Bundle.main.bundleIdentifier
    ) -> [AppRule] {
        incoming.reduce(into: existing) { result, rule in
            result = adding(rule, to: result, ownBundleID: ownBundleID)
        }
    }

    nonisolated static func presetID(for bundleID: String?, in rules: [AppRule]) -> UUID? {
        resolving(bundleID: bundleID, in: rules)?.presetID
    }

    nonisolated static func disablesTrail(for bundleID: String?, in rules: [AppRule]) -> Bool {
        resolving(bundleID: bundleID, in: rules)?.disablesTrail ?? false
    }

    /// 键盘 HUD 在这个 App 里是否允许显示：规则显式关掉就不显示，其余跟随全局。
    nonisolated static func isHUDAllowed(
        for bundleID: String?,
        in rules: [AppRule],
        globalEnabled: Bool
    ) -> Bool {
        guard globalEnabled else { return false }
        guard let rule = resolving(bundleID: bundleID, in: rules) else { return true }
        return rule.hudEnabled ?? true
    }
}
