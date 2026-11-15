import XCTest
@testable import ClickBoom

final class AppExclusionTests: XCTestCase {
    func testNormalizeTrimsAndLowercases() {
        XCTAssertEqual(AppExclusionLogic.normalize("  Com.Apple.Safari \n"), "com.apple.safari")
        XCTAssertNil(AppExclusionLogic.normalize(nil))
        XCTAssertNil(AppExclusionLogic.normalize("   "))
    }

    func testIsExcludedMatchesCaseInsensitively() {
        let list = [ExcludedApp(bundleID: "com.apple.Safari", name: "Safari")]
        XCTAssertTrue(AppExclusionLogic.isExcluded(bundleID: "COM.APPLE.SAFARI", in: list))
        XCTAssertTrue(AppExclusionLogic.isExcluded(bundleID: "  com.apple.safari ", in: list))
        XCTAssertFalse(AppExclusionLogic.isExcluded(bundleID: "com.apple.dt.Xcode", in: list))
        XCTAssertFalse(AppExclusionLogic.isExcluded(bundleID: nil, in: list), "拿不到 bundle id 时不能误排除")
    }

    func testAddingDeduplicatesAndUpdatesName() {
        let first = AppExclusionLogic.adding(
            ExcludedApp(bundleID: "com.apple.Safari", name: "Safari"),
            to: [],
            ownBundleID: "mumu.AIGG.clickBoom"
        )
        XCTAssertEqual(first.count, 1)

        let second = AppExclusionLogic.adding(
            ExcludedApp(bundleID: " COM.APPLE.SAFARI ", name: "Safari 浏览器"),
            to: first,
            ownBundleID: "mumu.AIGG.clickBoom"
        )
        XCTAssertEqual(second.count, 1, "同一个 App 不应重复加入")
        XCTAssertEqual(second[0].bundleID, "com.apple.safari")
        XCTAssertEqual(second[0].name, "Safari 浏览器")
    }

    func testAddingRejectsClickBoomItself() {
        let result = AppExclusionLogic.adding(
            ExcludedApp(bundleID: "mumu.AIGG.clickBoom", name: "ClickBoom"),
            to: [],
            ownBundleID: "mumu.AIGG.clickBoom"
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testAddingFallsBackToBundleIDWhenNameIsBlank() {
        let result = AppExclusionLogic.adding(
            ExcludedApp(bundleID: "com.example.tool", name: "   "),
            to: [],
            ownBundleID: "mumu.AIGG.clickBoom"
        )
        XCTAssertEqual(result.first?.name, "com.example.tool")
    }

    func testRemoving() {
        let list = [
            ExcludedApp(bundleID: "com.apple.Safari", name: "Safari"),
            ExcludedApp(bundleID: "com.apple.dt.Xcode", name: "Xcode")
        ]
        let removed = AppExclusionLogic.removing(
            ExcludedApp(bundleID: " COM.APPLE.SAFARI ", name: "Safari"),
            from: list
        )
        XCTAssertEqual(removed.map(\.bundleID), ["com.apple.dt.Xcode"])
    }
}
