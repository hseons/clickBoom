import AppKit
import Foundation

/// 被排除的 App：在这些 App 里不显示点击特效和滑动拖尾。
///
/// 录屏、视频会议、全屏游戏里往往不希望出现额外动画，
/// 用 bundle id 记录比 App 名称稳定（名称会随语言和版本变化）。
nonisolated struct ExcludedApp: Codable, Identifiable, Hashable {
    var bundleID: String
    var name: String

    init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }

    var id: String { bundleID }
}

/// 排除列表的纯规则：规范化、去重、增删。
enum AppExclusionLogic {
    /// bundle id 统一去空白 + 小写，手改配置或大小写不一致时也能匹配。
    nonisolated static func normalize(_ bundleID: String?) -> String? {
        guard let trimmed = bundleID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// 当前前台 App 是否在排除列表里；拿不到 bundle id 时不排除，避免特效莫名消失。
    nonisolated static func isExcluded(
        bundleID: String?,
        in excludedApps: [ExcludedApp]
    ) -> Bool {
        guard let target = normalize(bundleID) else { return false }
        return excludedApps.contains { normalize($0.bundleID) == target }
    }

    /// 加入列表：自动去重、更新名称，并拒绝把 ClickBoom 自己排除掉。
    nonisolated static func adding(
        _ app: ExcludedApp,
        to excludedApps: [ExcludedApp],
        ownBundleID: String? = Bundle.main.bundleIdentifier
    ) -> [ExcludedApp] {
        guard let bundleID = normalize(app.bundleID),
              bundleID != normalize(ownBundleID) else {
            return excludedApps
        }

        let name = app.name.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = excludedApps.filter { normalize($0.bundleID) != bundleID }
        updated.append(ExcludedApp(bundleID: bundleID, name: name.isEmpty ? bundleID : name))
        return updated
    }

    nonisolated static func removing(
        _ app: ExcludedApp,
        from excludedApps: [ExcludedApp]
    ) -> [ExcludedApp] {
        guard let bundleID = normalize(app.bundleID) else { return excludedApps }
        return excludedApps.filter { normalize($0.bundleID) != bundleID }
    }

    /// 可加入选择的 App：只列普通 Dock 应用，去掉自己、已在列表里的和没有 bundle id 的进程。
    @MainActor
    static func selectableRunningApps(
        excluding excludedApps: [ExcludedApp],
        ownBundleID: String? = Bundle.main.bundleIdentifier
    ) -> [ExcludedApp] {
        let excludedIDs = Set(excludedApps.compactMap { normalize($0.bundleID) })
        let ownID = normalize(ownBundleID)

        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> ExcludedApp? in
                guard let bundleID = normalize(app.bundleIdentifier),
                      bundleID != ownID,
                      !excludedIDs.contains(bundleID) else {
                    return nil
                }
                return ExcludedApp(bundleID: bundleID, name: app.localizedName ?? bundleID)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// 当前最前面的 App，供「添加当前 App」一键加入。
    @MainActor
    static func frontmostApp(ownBundleID: String? = Bundle.main.bundleIdentifier) -> ExcludedApp? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = normalize(app.bundleIdentifier),
              bundleID != normalize(ownBundleID) else {
            return nil
        }
        return ExcludedApp(bundleID: bundleID, name: app.localizedName ?? bundleID)
    }
}
