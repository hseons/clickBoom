import Foundation

struct PresetArchiveMergeResult {
    let presets: [PresetSnapshot]
    let summary: PresetImportSummary
}

/// 预设文件的编解码、校验与合并都集中在这里，便于单元测试覆盖，不依赖 UI 或 UserDefaults。
enum PresetArchiveCodec {
    static let maxFileSize = 5 * 1024 * 1024
    static let maxPresetsPerImport = 500

    static func encode(
        _ presets: [PresetSnapshot],
        exportedAt: Date = Date()
    ) throws -> Data {
        let archive = PresetArchive(
            schemaVersion: PresetArchive.currentSchemaVersion,
            exportedAt: exportedAt,
            presets: presets
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(archive)
    }

    static func decode(_ data: Data) throws -> [PresetSnapshot] {
        guard data.count <= maxFileSize else {
            throw PresetArchiveError.fileTooLarge
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(PresetArchive.self, from: data)
        guard archive.schemaVersion == PresetArchive.currentSchemaVersion else {
            throw PresetArchiveError.unsupportedSchema(archive.schemaVersion)
        }
        guard !archive.presets.isEmpty else {
            throw PresetArchiveError.emptyArchive
        }
        return archive.presets
    }

    static func merge(
        _ incoming: [PresetSnapshot],
        into existing: [PresetSnapshot]
    ) -> PresetArchiveMergeResult {
        var merged = existing
        var added = 0
        var updated = 0
        var renamed = 0

        for raw in incoming.prefix(maxPresetsPerImport) {
            var preset = sanitize(raw)
            let requestedName = preset.name

            if let index = merged.firstIndex(where: { $0.id == preset.id }) {
                preset.name = uniqueName(
                    requestedName,
                    excludingID: preset.id,
                    among: merged
                )
                if preset.name != requestedName { renamed += 1 }
                merged[index] = preset
                updated += 1
            } else {
                preset.name = uniqueName(
                    requestedName,
                    excludingID: nil,
                    among: merged
                )
                if preset.name != requestedName { renamed += 1 }
                merged.append(preset)
                added += 1
            }
        }

        return PresetArchiveMergeResult(
            presets: merged,
            summary: PresetImportSummary(
                added: added,
                updated: updated,
                renamed: renamed
            )
        )
    }

    static func sanitize(_ raw: PresetSnapshot) -> PresetSnapshot {
        var preset = raw
        let trimmedName = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
        preset.name = String(trimmedName.prefix(80))
        if preset.name.isEmpty { preset.name = "导入预设" }

        if EffectStyle(rawValue: preset.effect) == nil {
            preset.effect = EffectStyle.spark.rawValue
        }
        preset.colorHex = normalizedHex(preset.colorHex, fallback: "#FFFFFF")
        preset.count = min(20, max(3, preset.count))
        preset.size = clamped(preset.size, range: 1...30, fallback: 10)
        preset.radius = clamped(preset.radius, range: 5...100, fallback: 15)
        preset.durationMs = clamped(preset.durationMs, range: 100...2000, fallback: 400)
        preset.scale = clamped(preset.scale, range: 0.5...5, fallback: 1)
        preset.emoji = String(preset.emoji.prefix(64))
        if preset.emoji.isEmpty { preset.emoji = "✨" }

        if let style = preset.trailStyle, TrailStyle(rawValue: style) == nil {
            preset.trailStyle = nil
        }
        if let color = preset.trailColorHex {
            preset.trailColorHex = normalizedHex(color, fallback: "#FFFFFF")
        }
        if let width = preset.trailWidth {
            preset.trailWidth = clamped(width, range: 2...30, fallback: 10)
        }
        if let opacity = preset.trailOpacity {
            preset.trailOpacity = clamped(opacity, range: 0.2...1, fallback: 1)
        }
        if let lifetime = preset.trailLifetimeMs {
            preset.trailLifetimeMs = clamped(lifetime, range: 200...2000, fallback: 400)
        }
        if let trigger = preset.trailTriggerMode,
           TrailTriggerMode(rawValue: trigger) == nil {
            preset.trailTriggerMode = nil
        }

        if let color = preset.spotlightColorHex {
            preset.spotlightColorHex = normalizedHex(color, fallback: "#66E8FF")
        }
        if let size = preset.spotlightSize {
            preset.spotlightSize = clamped(size, range: 36...140, fallback: 72)
        }
        if let opacity = preset.spotlightOpacity {
            preset.spotlightOpacity = clamped(opacity, range: 0.15...1, fallback: 0.58)
        }
        if let color = preset.rightClickColorHex {
            preset.rightClickColorHex = normalizedHex(color, fallback: "#FF9F43")
        }
        if let color = preset.middleClickColorHex {
            preset.middleClickColorHex = normalizedHex(color, fallback: "#B48CFF")
        }
        return preset
    }

    static func uniqueName(
        _ proposedName: String,
        excludingID: UUID?,
        among presets: [PresetSnapshot]
    ) -> String {
        let names = Set(
            presets
                .filter { $0.id != excludingID }
                .map(\.name)
        )
        guard names.contains(proposedName) else { return proposedName }

        var index = 1
        while true {
            let suffix = index == 1 ? "（导入）" : "（导入 \(index)）"
            let candidate = proposedName + suffix
            if !names.contains(candidate) { return candidate }
            index += 1
        }
    }

    static func normalizedHex(_ raw: String, fallback: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let hex = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard hex.count == 6,
              hex.allSatisfy(\.isHexDigit) else {
            return fallback
        }
        return "#\(hex.uppercased())"
    }

    static func clamped(
        _ value: Double,
        range: ClosedRange<Double>,
        fallback: Double
    ) -> Double {
        guard value.isFinite else { return fallback }
        return min(range.upperBound, max(range.lowerBound, value))
    }
}
