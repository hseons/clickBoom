import XCTest
@testable import ClickBoom

final class PresetLibraryTests: XCTestCase {
    @MainActor
    private func preset(_ name: String) -> PresetSnapshot {
        PresetSnapshot(name: name, effect: "spark", colorHex: "#FFFFFF", count: 8,
                       size: 10, radius: 15, durationMs: 400, scale: 1, emoji: "✨")
    }

    @MainActor
    func testSearchCombinesTrimmedCaseInsensitiveNameAndFavoriteFilter() {
        var favorite = preset("Work 录屏")
        favorite.isFavorite = true
        let all = [favorite, preset("Work 直播"), preset("日常")]
        XCTAssertEqual(PresetLibraryLogic.filtered(all, query: " WORK ", favoritesOnly: false).count, 2)
        XCTAssertEqual(PresetLibraryLogic.filtered(all, query: "work", favoritesOnly: true), [favorite])
        XCTAssertTrue(PresetLibraryLogic.filtered(all, query: "无匹配", favoritesOnly: false).isEmpty)
    }

    @MainActor
    func testQuickAccessPrioritizesFavoritesThenRecentAndLimitsCount() {
        var favorite = preset("收藏")
        favorite.isFavorite = true
        var old = preset("以前使用")
        old.lastUsedAt = Date(timeIntervalSince1970: 1)
        var recent = preset("最近使用")
        recent.lastUsedAt = Date(timeIntervalSince1970: 2)
        let unused = preset("未使用")
        let all = [unused, old, recent, favorite]
        XCTAssertEqual(PresetLibraryLogic.quickAccess(all, limit: 3), [favorite, recent, old])
        XCTAssertEqual(PresetLibraryLogic.quickAccess(all, limit: 10), [favorite, recent, old, unused])
        XCTAssertTrue(PresetLibraryLogic.quickAccess(all, limit: 0).isEmpty)
        XCTAssertTrue(PresetLibraryLogic.quickAccess(all, limit: -1).isEmpty)
    }

    @MainActor
    func testQuickAccessPreservesManualOrderForFavoritesAndUnusedItems() {
        var first = preset("一")
        first.isFavorite = true
        var second = preset("二")
        second.isFavorite = true
        let all = [first, second, preset("三"), preset("四")]
        XCTAssertEqual(PresetLibraryLogic.quickAccess(all), all)
    }

    @MainActor
    func testRenamePreservesIdentityAndAvoidsDuplicateOrEmptyNames() {
        let first = preset("一")
        let second = preset("二")
        let all = [first, second]
        let renamed = PresetLibraryLogic.renamed(all, id: first.id, name: " 二 ")
        XCTAssertEqual(renamed[0].name, "二（导入）")
        XCTAssertEqual(renamed[0].id, first.id)
        XCTAssertEqual(renamed[1], second)
        XCTAssertEqual(PresetLibraryLogic.renamed(all, id: first.id, name: "  "), all)
        XCTAssertEqual(PresetLibraryLogic.renamed(all, id: UUID(), name: "三"), all)
    }

    @MainActor
    func testDuplicateCreatesIndependentIdentityAndUniqueName() {
        var original = preset("演示")
        original.isFavorite = true
        original.lastUsedAt = Date()
        let firstCopy = PresetLibraryLogic.duplicating([original], id: original.id)
        let all = PresetLibraryLogic.duplicating(firstCopy, id: original.id)
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(Set(all.map(\.id)).count, 3)
        XCTAssertEqual(Set(all.map(\.name)).count, 3)
        XCTAssertEqual(all[0], original)
        XCTAssertEqual(all[1].colorHex, original.colorHex)
        XCTAssertEqual(all[1].isFavorite, false)
        XCTAssertNil(all[1].lastUsedAt)
    }

    @MainActor
    func testMoveInBothDirectionsAndIgnoreUnknownOrSameTarget() {
        let a = preset("一"), b = preset("二"), c = preset("三")
        let all = [a, b, c]
        XCTAssertEqual(PresetLibraryLogic.moving(all, id: c.id, before: a.id), [c, a, b])
        XCTAssertEqual(PresetLibraryLogic.moving(all, id: a.id, before: c.id), [b, a, c])
        XCTAssertEqual(PresetLibraryLogic.moving(all, id: a.id, before: a.id), all)
        XCTAssertEqual(PresetLibraryLogic.moving(all, id: UUID(), before: c.id), all)
        XCTAssertEqual(PresetLibraryLogic.moving(all, id: a.id, before: UUID()), all)
    }

    @MainActor
    func testArchiveRoundTripPreservesOptionalLibraryMetadata() throws {
        var favorite = preset("收藏")
        favorite.isFavorite = true
        favorite.lastUsedAt = Date(timeIntervalSince1970: 123)
        let result = try PresetArchiveCodec.decode(PresetArchiveCodec.encode([favorite]))
        XCTAssertEqual(result, [favorite])
    }

    @MainActor
    private func withState(_ body: (AppState, UserDefaults) throws -> Void) rethrows {
        let suite = "ClickBoomTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(AppState(defaults: defaults), defaults)
    }

    @MainActor
    func testOverwriteRetainsIdentityFavoriteAndUsageAfterRestart() {
        withState { state, defaults in
            state.saveCurrentPreset(named: "日常")
            let id = state.savedPresets[0].id
            state.togglePresetFavorite(id)
            state.apply(state.savedPresets[0])
            let lastUsed = state.savedPresets[0].lastUsedAt
            state.particleCount = 12
            state.saveCurrentPreset(named: "日常")
            let reloaded = AppState(defaults: defaults)
            XCTAssertEqual(reloaded.savedPresets.count, 1)
            XCTAssertEqual(reloaded.savedPresets[0].id, id)
            XCTAssertEqual(reloaded.savedPresets[0].isFavorite, true)
            XCTAssertEqual(reloaded.savedPresets[0].lastUsedAt, lastUsed)
            XCTAssertEqual(reloaded.savedPresets[0].count, 12)
        }
    }

    @MainActor
    func testManagementOperationsPersistAndApplyUpdatesRecentUsage() {
        withState { state, defaults in
            state.savedPresets = [preset("一"), preset("二")]
            let id = state.savedPresets[0].id
            state.renamePreset(id, to: "重命名")
            state.duplicatePreset(id)
            let copyID = state.savedPresets[1].id
            state.movePreset(copyID, before: id)
            state.togglePresetFavorite(id)
            state.apply(state.savedPresets[0])
            let restored = AppState(defaults: defaults)
            XCTAssertEqual(restored.savedPresets, state.savedPresets)
            XCTAssertEqual(restored.savedPresets[0].id, copyID)
            XCTAssertNotNil(restored.savedPresets[0].lastUsedAt)
            XCTAssertEqual(restored.quickAccessPresets[0].id, id)
        }
    }

    @MainActor
    func testImportPreviewDoesNotMutateLibraryAndUndoSurvivesRestart() throws {
        try withState { state, defaults in
            let original = [preset("原预设")]
            state.savedPresets = original
            let incoming = [preset("新预设")]
            let data = try PresetArchiveCodec.encode(incoming)
            let preview = PresetArchiveCodec.merge(try PresetArchiveCodec.decode(data), into: state.savedPresets)
            XCTAssertEqual(preview.summary.added, 1)
            XCTAssertEqual(state.savedPresets, original)
            XCTAssertFalse(state.canUndoPresetImport)
            try state.importPresetArchive(from: data)
            let restored = AppState(defaults: defaults)
            XCTAssertTrue(restored.canUndoPresetImport)
            restored.undoPresetImport()
            XCTAssertEqual(restored.savedPresets, original)
            XCTAssertFalse(restored.canUndoPresetImport)
            XCTAssertEqual(AppState(defaults: defaults).savedPresets, original)
        }
    }

    @MainActor
    func testImportIntoEmptyLibraryCanBeUndone() throws {
        try withState { state, _ in
            try state.importPresetArchive(from: PresetArchiveCodec.encode([preset("新预设")]))
            XCTAssertTrue(state.canUndoPresetImport)
            state.undoPresetImport()
            XCTAssertTrue(state.savedPresets.isEmpty)
        }
    }

    @MainActor
    func testEditingAfterImportPreventsUndoFromOverwritingNewChanges() throws {
        try withState { state, _ in
            try state.importPresetArchive(from: PresetArchiveCodec.encode([preset("新预设")]))
            state.renamePreset(state.savedPresets[0].id, to: "导入后修改")
            XCTAssertFalse(state.canUndoPresetImport)
            state.undoPresetImport()
            XCTAssertEqual(state.savedPresets[0].name, "导入后修改")
        }
    }

    @MainActor
    func testFailedImportPreservesLibraryAndPreviousRecovery() throws {
        try withState { state, _ in
            try state.importPresetArchive(from: PresetArchiveCodec.encode([preset("新预设")]))
            let before = state.savedPresets
            XCTAssertThrowsError(try state.importPresetArchive(from: Data("invalid".utf8)))
            XCTAssertEqual(state.savedPresets, before)
            XCTAssertTrue(state.canUndoPresetImport)
        }
    }
}
