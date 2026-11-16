import SwiftUI

struct PresetLibraryView: View {
    @ObservedObject var appState: AppState
    @Binding var searchText: String
    @Binding var favoritesOnly: Bool
    let onRename: (PresetSnapshot) -> Void

    private var presets: [PresetSnapshot] {
        PresetLibraryLogic.filtered(appState.savedPresets, query: searchText, favoritesOnly: favoritesOnly)
    }

    private var canReorder: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !favoritesOnly
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("搜索预设名称", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                Toggle(isOn: $favoritesOnly) {
                    Image(systemName: favoritesOnly ? "star.fill" : "star")
                }
                .toggleStyle(.button)
                .help("只看收藏")
            }

            if presets.isEmpty {
                Text("没有匹配的预设。")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(presets) { preset in
                    SavedPresetChip(
                        preset: preset,
                        onApply: { appState.apply(preset) },
                        onDelete: { appState.deletePreset(preset) },
                        onRename: { onRename(preset) },
                        onDuplicate: { appState.duplicatePreset(preset.id) },
                        onFavorite: { appState.togglePresetFavorite(preset.id) },
                        onMoveUp: { move(preset, offset: -1) },
                        onMoveDown: { move(preset, offset: 1) },
                        canMoveUp: canReorder && appState.savedPresets.first?.id != preset.id,
                        canMoveDown: canReorder && appState.savedPresets.last?.id != preset.id
                    )
                    .draggable(preset.id.uuidString)
                    .dropDestination(for: String.self) { items, _ in
                        guard canReorder, items.count == 1,
                              let id = UUID(uuidString: items[0]),
                              id != preset.id,
                              appState.savedPresets.contains(where: { $0.id == id }) else { return false }
                        appState.movePreset(id, before: preset.id)
                        return true
                    }
                }
            }

            Text(canReorder ? "右键管理预设；拖到另一项前可排序，也可用右键上移 / 下移。" : "清除搜索并关闭收藏筛选后可排序。")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.4))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func move(_ preset: PresetSnapshot, offset: Int) {
        let all = appState.savedPresets
        guard let index = all.firstIndex(where: { $0.id == preset.id }),
              all.indices.contains(index + offset) else { return }
        if offset < 0 {
            appState.movePreset(preset.id, before: all[index - 1].id)
        } else {
            appState.movePreset(all[index + 1].id, before: preset.id)
        }
    }
}
