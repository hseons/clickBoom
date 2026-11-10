import XCTest
@testable import ClickBoom

final class VersionComparisonTests: XCTestCase {
    @MainActor
    func testNewerVersionAcceptsVPrefixAndMissingComponents() {
        XCTAssertTrue(UpdateChecker.isNewer("v1.3", than: "1.2.3"))
        XCTAssertFalse(UpdateChecker.isNewer("1.2.3", than: "v1.2.3"))
        XCTAssertTrue(AppVersionComparator.isNewer("1.2.10", than: "1.2.9"))
        XCTAssertFalse(AppVersionComparator.isNewer("1.3", than: "1.3.0"))
    }

    @MainActor
    func testPrereleaseSortsBelowStableVersion() {
        XCTAssertFalse(AppVersionComparator.isNewer("1.3.0-beta.2", than: "1.3.0"))
        XCTAssertTrue(AppVersionComparator.isNewer("1.3.0", than: "1.3.0-beta.2"))
        XCTAssertTrue(AppVersionComparator.isNewer("1.3.0-beta.3", than: "1.3.0-beta.2"))
    }
}
