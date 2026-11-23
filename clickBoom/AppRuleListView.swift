import SwiftUI

/// 「应用规则」：每个 App 单独决定静默、套用哪个预设、关掉拖尾、是否显示键盘 HUD。
/// 没配置的 App 一律沿用全局设置，所以这里只展示配过的条目。
struct AppRuleListView: View {
    @ObservedObject var appState: AppState

    @State private var searchText = ""
    @State private var selectableApps: [ExcludedApp] = []

    private var filteredRules: [AppRule] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return appState.appRules }
        return appState.appRules.filter {
            $0.name.localizedCaseInsensitiveContains(keyword)
                || $0.bundleID.localizedCaseInsensitiveContains(keyword)
        }
    }

    private var filteredSelectableApps: [ExcludedApp] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let configured = Set(appState.appRules.map(\.bundleID))
        return selectableApps.filter { app in
            guard !configured.contains(app.bundleID) else { return false }
            guard !keyword.isEmpty else { return true }
            return app.name.localizedCaseInsensitiveContains(keyword)
                || app.bundleID.localizedCaseInsensitiveContains(keyword)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("按 App 单独决定是否静默、套用哪个预设、关不关拖尾和键盘 HUD；没配置的 App 沿用全局设置。")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)

            searchField

            if filteredRules.isEmpty {
                Text(searchText.isEmpty ? "还没有为任何 App 配置规则" : "没有匹配的 App")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.3))
            } else {
                ForEach(filteredRules) { rule in
                    ruleRow(rule)
                }
            }

            Menu {
                if filteredSelectableApps.isEmpty {
                    Button(searchText.isEmpty ? "没有可添加的 App" : "没有匹配的 App") {}
                        .disabled(true)
                } else {
                    ForEach(filteredSelectableApps) { app in
                        Button(app.name) {
                            appState.addAppRule(AppRule(bundleID: app.bundleID, name: app.name, silence: true))
                            refreshSelectableApps()
                        }
                    }
                }
            } label: {
                Label("添加 App 规则", systemImage: "plus.circle")
                    .font(.system(size: 12, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Text("切到某个 App 时才套用它的预设；离开后不强制还原，避免覆盖你手动调好的参数。")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.3))
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear(perform: refreshSelectableApps)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.35))
            TextField("搜索 App", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundColor(.white.opacity(0.35))
                .help("清空搜索")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.07))
        .cornerRadius(7)
    }

    @ViewBuilder
    private func ruleRow(_ rule: AppRule) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "app.badge.checkmark")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
                VStack(alignment: .leading, spacing: 1) {
                    Text(rule.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                    Text(rule.bundleID)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                }
                Spacer()
                Button {
                    appState.removeAppRule(bundleID: rule.bundleID)
                    refreshSelectableApps()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(.white.opacity(0.35))
                .help("删除这条规则")
            }

            HStack(spacing: 12) {
                Toggle("静默", isOn: binding(rule, \.silence))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(.orange)

                Toggle("关拖尾", isOn: binding(rule, \.disablesTrail))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(.pink)

                Spacer()
            }

            HStack(spacing: 10) {
                Menu {
                    Button("不套用预设") {
                        update(rule.bundleID) { $0.presetID = nil }
                    }
                    Divider()
                    if appState.savedPresets.isEmpty {
                        Text("还没有自定义预设")
                    } else {
                        ForEach(appState.savedPresets) { preset in
                            Button(preset.name) {
                                update(rule.bundleID) { $0.presetID = preset.id }
                            }
                        }
                    }
                } label: {
                    Label(presetTitle(for: rule), systemImage: "slider.horizontal.3")
                        .font(.system(size: 11))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Menu {
                    Button("HUD 跟随全局") { update(rule.bundleID) { $0.hudEnabled = nil } }
                    Button("总是显示 HUD") { update(rule.bundleID) { $0.hudEnabled = true } }
                    Button("不显示 HUD") { update(rule.bundleID) { $0.hudEnabled = false } }
                } label: {
                    Label(hudTitle(for: rule), systemImage: "keyboard")
                        .font(.system(size: 11))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Spacer()
            }
        }
        .padding(9)
        .background(Color.white.opacity(0.05))
        .cornerRadius(9)
    }

    private func presetTitle(for rule: AppRule) -> String {
        guard let id = rule.presetID,
              let preset = appState.savedPresets.first(where: { $0.id == id }) else {
            return "不套用预设"
        }
        return "预设：\(preset.name)"
    }

    private func hudTitle(for rule: AppRule) -> String {
        switch rule.hudEnabled {
        case .none: return "HUD：跟随全局"
        case .some(true): return "HUD：总是显示"
        case .some(false): return "HUD：不显示"
        }
    }

    private func binding(_ rule: AppRule, _ keyPath: WritableKeyPath<AppRule, Bool>) -> Binding<Bool> {
        Binding(
            get: {
                appState.appRules.first(where: { $0.bundleID == rule.bundleID })?[keyPath: keyPath]
                    ?? rule[keyPath: keyPath]
            },
            set: { newValue in
                update(rule.bundleID) { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private func update(_ bundleID: String, _ mutate: (inout AppRule) -> Void) {
        guard var rule = appState.appRules.first(where: { $0.bundleID == bundleID }) else { return }
        mutate(&rule)
        appState.updateAppRule(rule)
    }

    private func refreshSelectableApps() {
        selectableApps = AppExclusionLogic.selectableRunningApps(excluding: [])
    }
}
