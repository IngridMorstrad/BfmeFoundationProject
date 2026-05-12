import XCTest
@testable import BfmeKitCore

final class DataModelsTests: XCTestCase {
    func testStandardBfme1Factions() {
        let factions = BfmeFaction.standardBfme1Factions()
        XCTAssertEqual(factions.count, 4)
        XCTAssertEqual(factions.first?.name, "Rohan")
        XCTAssertEqual(factions.first?.id, 3)
    }

    func testBfmeDefaultsDictionariesMatchLegacyLayout() {
        XCTAssertEqual(BfmeDefaults.defaultGameExecutableNames[0], "lotrbfme.exe")
        XCTAssertEqual(BfmeDefaults.defaultGameExecutableNames[1], "lotrbfme2.exe")
        XCTAssertEqual(BfmeDefaults.defaultGameExecutableNames[2], "lotrbfme2ep1.exe")
        XCTAssertTrue(BfmeDefaults.defaultOptions.contains("Resolution = 1920 1080"))
    }

    func testRgbaArgbRoundTrip() {
        let c = RGBA(argb: 0x11223344)
        XCTAssertEqual(c.a, 0x11)
        XCTAssertEqual(c.r, 0x22)
        XCTAssertEqual(c.g, 0x33)
        XCTAssertEqual(c.b, 0x44)
        XCTAssertEqual(c.argb, 0x11223344)
    }

    func testResizeToFitMaintainsAspect() {
        let result = RectUtils.resizeToFit(
            sourceSize: SizeF(width: 200, height: 100),
            targetSize: SizeF(width: 400, height: 400)
        )
        XCTAssertEqual(result.width, 400.0, accuracy: 1e-6)
        XCTAssertEqual(result.height, 200.0, accuracy: 1e-6)
    }

    func testRandomizeSpotsChangesOrderDeterministicallyOverManyRuns() {
        let spots = (0..<10).map { BfmeSpot(x: Float($0), y: 0, team: 0, index: $0) }
        var map = BfmeMap(id: "m", name: "M", game: 0, preview: "", width: 100, height: 100, spots: spots)
        // Not every shuffle will differ, but across 50 attempts we expect at
        // least one permutation change.
        var changed = false
        for _ in 0..<50 {
            map.randomizeSpots()
            if map.spots != spots { changed = true; break }
        }
        XCTAssertTrue(changed)
    }
}
