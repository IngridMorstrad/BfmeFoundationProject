import XCTest
@testable import BfmeKit
import BfmeKitCore

final class BfmeColorImporterTests: XCTestCase {
    func testParsesCanonicalBlocks() {
        let source = """
        // Sample multiplayer.ini excerpt
        MultiplayerColor ColorRed
          RgbColor = R:200 G:10 B:10
          TooltipName = TOOLTIP:Red
        End

        MultiplayerColor ColorBlue
            RgbColor = R:30  G:60   B:220
        End

        ; a comment
        MultiplayerColor Pink
          RgbColor = R:255 G:128 B:200
        End
        """

        let colors = BfmeColorImporter.importColors(fromMultiplayerIni: source)
        XCTAssertEqual(colors.count, 3)

        XCTAssertEqual(colors[0].name, "Red")
        XCTAssertEqual(colors[0].id, 0)
        XCTAssertEqual(colors[0].previewColor, RGBA(r: 200, g: 10, b: 10, a: 255))

        XCTAssertEqual(colors[1].name, "Blue")
        XCTAssertEqual(colors[1].id, 1)
        XCTAssertEqual(colors[1].previewColor, RGBA(r: 30, g: 60, b: 220, a: 255))

        XCTAssertEqual(colors[2].name, "Pink")
        XCTAssertEqual(colors[2].id, 2)
        XCTAssertEqual(colors[2].previewColor, RGBA(r: 255, g: 128, b: 200, a: 255))
    }

    func testSkipsMalformedBlocks() {
        let source = """
        MultiplayerColor ColorBad
          RgbColor = R:xxx G:10 B:10
        End
        MultiplayerColor ColorOk
          RgbColor = R:1 G:2 B:3
        End
        """
        let colors = BfmeColorImporter.importColors(fromMultiplayerIni: source)
        XCTAssertEqual(colors.count, 1)
        XCTAssertEqual(colors[0].name, "Ok")
        XCTAssertEqual(colors[0].previewColor, RGBA(r: 1, g: 2, b: 3, a: 255))
    }
}
