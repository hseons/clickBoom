import Foundation

/// 预设管理规则；顺序直接沿用数组顺序，旧归档无需迁移。
enum PresetLibraryLogic {
    static func filtered(_ presets: [PresetSnapshot], query: String, favoritesOnly: Bool) -> [PresetSnapshot] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return presets.filter {
            (!favoritesOnly || $0.isFavorite == true)
                && (keyword.isEmpty || $0.name.localizedCaseInsensitiveContains(keyword))
        }
    }

    /// 收藏保持手动顺序，其余按最近使用排序；未使用过的项目在首次使用前也可发现。
    static func quickAccess(_ presets: [PresetSnapshot], limit: Int = 8) -> [PresetSnapshot] {
        let favorites = presets.filter { $0.isFavorite == true }
        let others = presets.enumerated().filter { $0.element.isFavorite != true }.sorted {
            let lhs = $0.element.lastUsedAt ?? .distantPast
            let rhs = $1.element.lastUsedAt ?? .distantPast
            return lhs == rhs ? $0.offset < $1.offset : lhs > rhs
        }.map(\.element)
        return Array((favorites + others).prefix(max(0, limit)))
    }

    static func renamed(_ presets: [PresetSnapshot], id: UUID, name: String) -> [PresetSnapshot] {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !trimmed.isEmpty, let index = presets.firstIndex(where: { $0.id == id }) else { return presets }
        var result = presets
        result[index].name = PresetArchiveCodec.uniqueName(trimmed, excludingID: id, among: presets)
        return result
    }

    static func duplicating(_ presets: [PresetSnapshot], id: UUID) -> [PresetSnapshot] {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return presets }
        var copy = presets[index]
        copy.id = UUID()
        copy.name = PresetArchiveCodec.uniqueName(String(copy.name.prefix(76)) + " 副本", excludingID: nil, among: presets)
        copy.isFavorite = false
        copy.lastUsedAt = nil
        var result = presets
        result.insert(copy, at: index + 1)
        return result
    }

    static func moving(_ presets: [PresetSnapshot], id: UUID, before targetID: UUID) -> [PresetSnapshot] {
        guard id != targetID,
              let source = presets.firstIndex(where: { $0.id == id }),
              presets.contains(where: { $0.id == targetID }) else { return presets }
        var result = presets
        let preset = result.remove(at: source)
        guard let target = result.firstIndex(where: { $0.id == targetID }) else { return presets }
        result.insert(preset, at: target)
        return result
    }
}

/// 保存导入前后的列表；导入后发生编辑时禁止撤销，避免覆盖新修改。
struct PresetImportRecovery: Codable {
    let previous: [PresetSnapshot]
    let imported: [PresetSnapshot]

    func canRestore(over current: [PresetSnapshot]) -> Bool {
        current == imported
    }
}
