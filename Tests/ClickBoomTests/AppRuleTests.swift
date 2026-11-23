import XCTest
@testable import ClickBoom

final class AppRuleTests: XCTestCase {
    private let ownBundleID = "dev.clickboom.app"

    func testAddingRejectsOwnBundleAndDuplicates() {
        let rule = AppRule(bundleID: ownBundleID.uppercased(), name: "ClickBoom")
        XCTAssertTrue(AppRuleLogic.adding(rule, to: [], ownBundleID: ownBundleID).isEmpty)

        let first = AppRule(bundleID: "com.apple.Keynote", name: "Keynote", silence: true)
        let second = AppRule(bundleID: "COM.APPLE.KEYNOTE ", name: "  Keynote 2  ", silence: false)
        let rules = AppRuleLogic.adding(second, to: AppRuleLogic.adding(first, to: [], ownBundleID: ownBundleID),
                                        ownBundleID: ownBundleID)

        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules[0].bundleID, "com.apple.keynote")
        XCTAssertEqual(rules[0].name, "Keynote 2")
        XCTAssertFalse(rules[0].silence)
    }

    func testAddingFallsBackToBundleIDWhenNameIsBlank() {
        let rules = AppRuleLogic.adding(
            AppRule(bundleID: "com.example.app", name: "   "),
            to: [],
            ownBundleID: ownBundleID
        )

        XCTAssertEqual(rules.first?.name, "com.example.app")
    }

    func testResolvingIgnoresCaseAndWhitespace() {
        let rules = [AppRule(bundleID: "com.apple.Keynote", name: "Keynote", presetID: UUID())]

        XCTAssertNotNil(AppRuleLogic.resolving(bundleID: " COM.APPLE.KEYNOTE\n", in: rules))
        XCTAssertNil(AppRuleLogic.resolving(bundleID: "com.apple.Pages", in: rules))
        XCTAssertNil(AppRuleLogic.resolving(bundleID: nil, in: rules))
        XCTAssertNil(AppRuleLogic.resolving(bundleID: "   ", in: rules))
    }

    func testUpdatingOnlyTouchesRuleFieldsAndKeepsNameWhenBlank() {
        let original = AppRule(bundleID: "com.example.app", name: "示例", silence: true)
        let patch = AppRule(bundleID: "COM.EXAMPLE.APP", name: "  ", silence: false,
                            presetID: UUID(), disablesTrail: true, hudEnabled: false)

        let updated = AppRuleLogic.updating(patch, in: [original])

        XCTAssertEqual(updated.count, 1)
        XCTAssertEqual(updated[0].name, "示例")
        XCTAssertFalse(updated[0].silence)
        XCTAssertEqual(updated[0].presetID, patch.presetID)
        XCTAssertTrue(updated[0].disablesTrail)
        XCTAssertEqual(updated[0].hudEnabled, false)
    }

    func testUpdatingUnknownRuleKeepsListUnchanged() {
        let rules = [AppRule(bundleID: "com.example.app", name: "示例")]
        let patch = AppRule(bundleID: "com.other.app", name: "别的", silence: true)

        XCTAssertEqual(AppRuleLogic.updating(patch, in: rules), rules)
    }

    func testExclusionsOnlyContainSilencedRulesSortedByName() {
        let rules = [
            AppRule(bundleID: "b.app", name: "Bravo", silence: true),
            AppRule(bundleID: "a.app", name: "Alpha", silence: false),
            AppRule(bundleID: "c.app", name: "Charlie", silence: true)
        ]

        let exclusions = AppRuleLogic.exclusions(from: rules)

        XCTAssertEqual(exclusions.map(\.name), ["Bravo", "Charlie"])
    }

    func testLegacyExclusionsBecomeSilentRules() {
        let exclusions = [ExcludedApp(bundleID: "com.example.app", name: "示例")]

        let rules = AppRuleLogic.rules(from: exclusions)

        XCTAssertEqual(rules.count, 1)
        XCTAssertTrue(rules[0].silence)
        XCTAssertNil(rules[0].presetID)
        XCTAssertFalse(rules[0].disablesTrail)
        XCTAssertNil(rules[0].hudEnabled)
    }

    func testRuleLookupsFollowGlobalDefaultsWhenNoRuleMatches() {
        let preset = UUID()
        let rules = [AppRule(bundleID: "com.example.app", name: "示例", presetID: preset, disablesTrail: true)]

        XCTAssertEqual(AppRuleLogic.presetID(for: "COM.EXAMPLE.APP", in: rules), preset)
        XCTAssertNil(AppRuleLogic.presetID(for: "com.other.app", in: rules))
        XCTAssertTrue(AppRuleLogic.disablesTrail(for: "com.example.app", in: rules))
        XCTAssertFalse(AppRuleLogic.disablesTrail(for: "com.other.app", in: rules))
    }

    func testHUDVisibilityHonoursGlobalSwitchAndPerAppOverride() {
        let rules = [
            AppRule(bundleID: "quiet.app", name: "Quiet", hudEnabled: false),
            AppRule(bundleID: "loud.app", name: "Loud", hudEnabled: true)
        ]

        XCTAssertFalse(AppRuleLogic.isHUDAllowed(for: "quiet.app", in: rules, globalEnabled: true))
        XCTAssertTrue(AppRuleLogic.isHUDAllowed(for: "loud.app", in: rules, globalEnabled: true))
        XCTAssertTrue(AppRuleLogic.isHUDAllowed(for: "other.app", in: rules, globalEnabled: true))
        XCTAssertFalse(AppRuleLogic.isHUDAllowed(for: "loud.app", in: rules, globalEnabled: false))
    }

    func testRuleCodableRoundTripKeepsEveryField() throws {
        let rule = AppRule(bundleID: "com.example.app", name: "示例", silence: true,
                           presetID: UUID(), disablesTrail: true, hudEnabled: false)

        let data = try JSONEncoder().encode([rule])
        let decoded = try JSONDecoder().decode([AppRule].self, from: data)

        XCTAssertEqual(decoded, [rule])
    }

    func testBackupV2KeepsRulesAndRejectsNewerSchema() throws {
        let rules = [AppRule(bundleID: "com.example.app", name: "示例", silence: true)]
        let backup = SettingsBackup(
            hotKeySpec: HotKeySpec.default.storageValue,
            hotKeyEnabled: true,
            autoSilenceInFullScreen: true,
            excludedApps: [],
            appRules: rules
        )

        let decoded = try SettingsBackupLogic.decode(SettingsBackupLogic.encode(backup))

        XCTAssertEqual(decoded.schemaVersion, 2)
        XCTAssertEqual(decoded.appRules, rules)
        XCTAssertEqual(SettingsBackupLogic.rules(from: decoded), rules)

        var newer = backup
        newer.schemaVersion = 3
        XCTAssertThrowsError(try SettingsBackupLogic.decode(JSONEncoder().encode(newer)))
    }

    func testBackupV1RulesAreDerivedFromExclusions() throws {
        let legacy = SettingsBackup(
            schemaVersion: 1,
            hotKeySpec: HotKeySpec.default.storageValue,
            hotKeyEnabled: false,
            autoSilenceInFullScreen: false,
            excludedApps: [
                ExcludedApp(bundleID: "com.example.app", name: "示例"),
                ExcludedApp(bundleID: Bundle.main.bundleIdentifier ?? ownBundleID, name: "ClickBoom")
            ]
        )

        let decoded = try SettingsBackupLogic.decode(JSONEncoder().encode(legacy))
        let rules = SettingsBackupLogic.rules(from: decoded)

        XCTAssertEqual(rules.count, 1, "自身应该被规则合并过滤掉")
        XCTAssertEqual(rules[0].bundleID, "com.example.app")
        XCTAssertTrue(rules[0].silence)
    }

    func testImportedRulesWinOverLegacyExclusions() {
        let custom = AppRule(bundleID: "com.example.app", name: "示例", silence: false, disablesTrail: true)
        let backup = SettingsBackup(
            hotKeySpec: HotKeySpec.default.storageValue,
            hotKeyEnabled: true,
            autoSilenceInFullScreen: false,
            excludedApps: [ExcludedApp(bundleID: "com.example.app", name: "示例")],
            appRules: [custom]
        )

        XCTAssertEqual(SettingsBackupLogic.rules(from: backup), [custom])
    }
}
