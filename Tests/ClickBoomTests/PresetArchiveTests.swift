import XCTest
@testable import ClickBoom

final class PresetArchiveTests: XCTestCase {
    @MainActor
    func testArchiveRoundTripPreservesPresetFields() throws {
        let preset = makePreset(name: "录屏", colorHex: "#66e8ff")
        let data = try PresetArchiveCodec.encode([preset])
        let decoded = try PresetArchiveCodec.decode(data)

        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].id, preset.id)
        XCTAssertEqual(decoded[0].name, preset.name)
        XCTAssertEqual(decoded[0].colorHex, preset.colorHex)
        XCTAssertEqual(decoded[0].trailStyle, "neon")
        XCTAssertEqual(decoded[0].spotlightSize, 72)
    }

    @MainActor
    func testOldArchiveWithoutOptionalFieldsStillDecodes() throws {
        let json = """
        {
          "schemaVersion": 1,
          "exportedAt": "2026-11-10T07:00:00Z",
          "presets": [{
            "id": "11111111-1111-1111-1111-111111111111",
            "name": "旧预设",
            "effect": "spark",
            "colorHex": "#FFFFFF",
            "count": 6,
            "size": 6,
            "radius": 12,
            "durationMs": 280,
            "scale": 0.85,
            "emoji": "✨"
          }]
        }
        """

        let decoded = try PresetArchiveCodec.decode(Data(json.utf8))

        XCTAssertEqual(decoded.count, 1)
        XCTAssertNil(decoded[0].trailEnabled)
        XCTAssertNil(decoded[0].spotlightEnabled)
    }

    @MainActor
    func testArchiveRejectsUnsupportedSchemaAndEmptyPresets() {
        let unsupported = Data("""
        {
          "schemaVersion": 2,
          "exportedAt": "2026-11-10T07:00:00Z",
          "presets": []
        }
        """.utf8)
        let empty = Data("""
        {
          "schemaVersion": 1,
          "exportedAt": "2026-11-10T07:00:00Z",
          "presets": []
        }
        """.utf8)

        XCTAssertThrowsError(try PresetArchiveCodec.decode(unsupported)) { error in
            guard case PresetArchiveError.unsupportedSchema(2) = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
        XCTAssertThrowsError(try PresetArchiveCodec.decode(empty)) { error in
            guard case PresetArchiveError.emptyArchive = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    @MainActor
    func testArchiveRejectsOversizedFileBeforeDecoding() {
        let data = Data(repeating: 0, count: PresetArchiveCodec.maxFileSize + 1)

        XCTAssertThrowsError(try PresetArchiveCodec.decode(data)) { error in
            guard case PresetArchiveError.fileTooLarge = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    @MainActor
    func testSanitizeRepairsOutOfRangeValuesAndInvalidEnums() {
        var preset = makePreset(name: "   ", colorHex: "bad")
        preset.effect = "missing"
        preset.count = 999
        preset.size = .nan
        preset.radius = -1
        preset.durationMs = .infinity
        preset.scale = 99
        preset.emoji = ""
        preset.trailStyle = "missing"
        preset.trailOpacity = 0
        preset.spotlightColorHex = "#12"

        let sanitized = PresetArchiveCodec.sanitize(preset)

        XCTAssertEqual(sanitized.name, "导入预设")
        XCTAssertEqual(sanitized.effect, EffectStyle.spark.rawValue)
        XCTAssertEqual(sanitized.colorHex, "#FFFFFF")
        XCTAssertEqual(sanitized.count, 20)
        XCTAssertEqual(sanitized.size, 10)
        XCTAssertEqual(sanitized.radius, 5)
        XCTAssertEqual(sanitized.durationMs, 400)
        XCTAssertEqual(sanitized.scale, 5)
        XCTAssertEqual(sanitized.emoji, "✨")
        XCTAssertNil(sanitized.trailStyle)
        XCTAssertEqual(sanitized.trailOpacity, 0.2)
        XCTAssertEqual(sanitized.spotlightColorHex, "#66E8FF")
    }

    @MainActor
    func testMergeUpdatesSameIDAndRenamesConflictingName() {
        let existingID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let newID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        var existing = makePreset(name: "日常", colorHex: "#FFFFFF")
        existing.id = existingID

        var updated = makePreset(name: "日常", colorHex: "#112233")
        updated.id = existingID
        var imported = makePreset(name: "日常", colorHex: "#445566")
        imported.id = newID

        let result = PresetArchiveCodec.merge([updated, imported], into: [existing])

        XCTAssertEqual(result.presets.count, 2)
        XCTAssertEqual(result.presets[0].id, existingID)
        XCTAssertEqual(result.presets[0].colorHex, "#112233")
        XCTAssertEqual(result.presets[0].name, "日常")
        XCTAssertEqual(result.presets[1].id, newID)
        XCTAssertEqual(result.presets[1].name, "日常（导入）")
        XCTAssertEqual(result.summary.added, 1)
        XCTAssertEqual(result.summary.updated, 1)
        XCTAssertEqual(result.summary.renamed, 1)
        XCTAssertEqual(result.summary.total, 2)
    }

    @MainActor
    private func makePreset(name: String, colorHex: String) -> PresetSnapshot {
        PresetSnapshot(
            name: name,
            effect: EffectStyle.spark.rawValue,
            colorHex: colorHex,
            count: 6,
            size: 6,
            radius: 12,
            durationMs: 280,
            scale: 0.85,
            emoji: "✨",
            trailEnabled: true,
            trailStyle: TrailStyle.neon.rawValue,
            trailColorHex: "#66E8FF",
            trailFollowsColor: true,
            trailWidth: 9,
            trailOpacity: 0.72,
            trailLifetimeMs: 560,
            trailTriggerMode: TrailTriggerMode.always.rawValue,
            spotlightEnabled: true,
            spotlightColorHex: "#FF77C8",
            spotlightSize: 72,
            spotlightOpacity: 0.52,
            distinguishMouseButtons: true,
            rightClickColorHex: "#FF9F43",
            middleClickColorHex: "#B48CFF"
        )
    }
}
