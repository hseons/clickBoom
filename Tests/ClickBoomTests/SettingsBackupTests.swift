import XCTest
@testable import ClickBoom

final class SettingsBackupTests: XCTestCase {
    private let ownBundleID = "mumu.AIGG.clickBoom"

    private func makeBackup() -> SettingsBackup {
        SettingsBackup(
            hotKeySpec: "11:4352",
            hotKeyEnabled: true,
            autoSilenceInFullScreen: false,
            excludedApps: [
                ExcludedApp(bundleID: "com.apple.Safari", name: "Safari"),
                ExcludedApp(bundleID: "com.apple.QuickTimePlayerX", name: "QuickTime Player")
            ]
        )
    }

    func testEncodeDecodeRoundTrip() throws {
        let backup = makeBackup()
        let data = try SettingsBackupLogic.encode(backup)
        let decoded = try SettingsBackupLogic.decode(data)
        XCTAssertEqual(decoded, backup)
        XCTAssertEqual(decoded.schemaVersion, SettingsBackupLogic.schemaVersion)
    }

    func testFutureSchemaIsRejected() throws {
        let json = """
        {
          "schemaVersion": 99,
          "hotKeySpec": "11:4352",
          "hotKeyEnabled": true,
          "autoSilenceInFullScreen": true,
          "excludedApps": []
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try SettingsBackupLogic.decode(json)) { error in
            XCTAssertEqual(error as? SettingsBackupError, .unsupportedVersion(99))
        }
    }

    func testMergingExclusionsDeduplicatesAndSkipsSelf() {
        let incoming = [
            ExcludedApp(bundleID: " COM.APPLE.SAFARI ", name: "Safari"),
            ExcludedApp(bundleID: "com.apple.safari", name: "Safari 浏览器"),
            ExcludedApp(bundleID: ownBundleID, name: "ClickBoom"),
            ExcludedApp(bundleID: "com.apple.QuickTimePlayerX", name: "QuickTime Player")
        ]

        let merged = SettingsBackupLogic.mergingExclusions(incoming, ownBundleID: ownBundleID)

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.map(\.bundleID), ["com.apple.safari", "com.apple.quicktimeplayerx"])
        XCTAssertEqual(merged.first?.name, "Safari 浏览器", "同名条目应以最后一次的名称为准")
    }

    func testEmptyBackupNeedsNoExclusions() throws {
        let backup = SettingsBackup(
            hotKeySpec: HotKeySpec.default.storageValue,
            hotKeyEnabled: true,
            autoSilenceInFullScreen: true,
            excludedApps: []
        )
        let decoded = try SettingsBackupLogic.decode(try SettingsBackupLogic.encode(backup))
        XCTAssertTrue(decoded.excludedApps.isEmpty)
    }

    func testQuietHoursWeekdaysRoundTripAndApply() throws {
        let backup = SettingsBackup(
            hotKeySpec: HotKeySpec.default.storageValue,
            hotKeyEnabled: true,
            autoSilenceInFullScreen: true,
            excludedApps: [],
            quietHoursEnabled: true,
            quietHoursStartMinutes: 22 * 60,
            quietHoursEndMinutes: 8 * 60,
            quietHoursWeekdays: QuietHours.weekdaysMask
        )
        let decoded = try SettingsBackupLogic.decode(try SettingsBackupLogic.encode(backup))
        XCTAssertEqual(decoded.quietHoursWeekdays, QuietHours.weekdaysMask)

        let merged = decoded.applyingQuietHours(to: QuietHours())
        XCTAssertEqual(merged.weekdayMask, QuietHours.weekdaysMask)
        XCTAssertEqual(merged.startMinutes, 22 * 60)
        XCTAssertTrue(merged.isEnabled)
    }

    func testOldBackupWithoutWeekdaysKeepsCurrentMask() {
        let current = QuietHours(isEnabled: true, weekdayMask: QuietHours.weekendMask)
        let old = SettingsBackup(
            hotKeySpec: HotKeySpec.default.storageValue,
            hotKeyEnabled: true,
            autoSilenceInFullScreen: true,
            excludedApps: []
        )
        XCTAssertEqual(old.applyingQuietHours(to: current).weekdayMask, QuietHours.weekendMask)
    }
}
