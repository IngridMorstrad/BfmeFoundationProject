import XCTest
@testable import BfmeKitCore

final class FilenameUtilsTests: XCTestCase {
    func testSigilGroupPrecedenceForBfme2() {
        // BFME2 (game != 0): inside a sigil group, higher weight wins and
        // ties break ascending by name.
        let files = [
            "mod_a.big",
            "!a.big",
            "!!b.big",
            "#z.big",
            "_base.big"
        ]
        let ordered = FilenameUtils.orderFiles(files, game: 1)
        // "!!b.big" has weight 2 and group 100: loads first.
        // "!a.big"  has weight 1 and group 100: next.
        // "#z.big"  group 99.
        // "_base.big" group 98.
        // "mod_a.big" group 0.
        XCTAssertEqual(ordered, ["!!b.big", "!a.big", "#z.big", "_base.big", "mod_a.big"])
    }

    func testBfme1BaseGroupSortsAscendingByName() {
        let files = ["c.big", "a.big", "b.big"]
        let ordered = FilenameUtils.orderFiles(files, game: 0)
        XCTAssertEqual(ordered, ["a.big", "b.big", "c.big"])
    }

    func testBfme1BangGroupSortsDescendingByName() {
        // BFME1 special case: sigil groups sort weight ASC then name DESC.
        let files = ["!a.big", "!b.big", "!c.big"]
        let ordered = FilenameUtils.orderFiles(files, game: 0)
        XCTAssertEqual(ordered, ["!c.big", "!b.big", "!a.big"])
    }

    func testExtensionIsStrippedBeforePrefixCheck() {
        // Make sure the prefix detection works on the filename stem, not on
        // any leading directory component.
        let files = ["path/to/!foo.big", "path/to/bar.big"]
        let ordered = FilenameUtils.orderFiles(files, game: 1)
        XCTAssertEqual(ordered, ["path/to/!foo.big", "path/to/bar.big"])
    }
}
