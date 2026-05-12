import XCTest
@testable import BfmeLauncherApp

final class SystemDisplayManagerTests: XCTestCase {
    func testPrimaryScreenResolutionHasPositiveDimensions() {
        let size = SystemDisplayManager.getPrimaryScreenResolution()
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertGreaterThan(size.height, 0)
    }

    #if canImport(AppKit)
    func testSnapshotRoundTripsThroughJSON() throws {
        let snapshot = SystemDisplayManager.snapshot()
        XCTAssertGreaterThan(snapshot.primary.width, 0)
        XCTAssertGreaterThan(snapshot.primary.height, 0)
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SystemDisplayManager.ScreenSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }
    #endif

    func testSupportedResolutionsListIsNonNegative() {
        // On Linux the stub returns the fallback list; on macOS it returns
        // whatever CGDisplayCopyAllDisplayModes reports. Both cases must be
        // non-negative and sorted ascending by width/height (after the 3
        // smallest are dropped).
        let list = SystemDisplayManager.getAllSupportedResolutions()
        for size in list {
            XCTAssertGreaterThan(size.width, 0)
            XCTAssertGreaterThan(size.height, 0)
        }
        for (prev, next) in zip(list, list.dropFirst()) {
            if prev.width == next.width {
                XCTAssertLessThanOrEqual(prev.height, next.height)
            } else {
                XCTAssertLessThan(prev.width, next.width)
            }
        }
    }
}
