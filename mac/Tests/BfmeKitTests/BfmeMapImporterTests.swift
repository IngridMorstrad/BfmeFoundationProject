import XCTest
@testable import BfmeKit
import BfmeKitCore

#if canImport(CoreGraphics)
import CoreGraphics
#endif

final class BfmeMapImporterTests: XCTestCase {
    func testGeneratePreviewComposesNonEmptyBitmap() {
        let map = BfmeMap(
            id: "maps/fourplayer.map",
            name: "Four Player",
            game: 1,
            preview: "",
            width: 640,
            height: 480,
            spots: [
                BfmeSpot(x: 0.25, y: 0.25, team: 0, index: 0),
                BfmeSpot(x: 0.75, y: 0.75, team: 1, index: 1)
            ]
        )

        let bitmap = BfmeMapImporter.generateMapPreviewBitmap(map: map)
        XCTAssertNotNil(bitmap)
        guard let bitmap else { return }
        XCTAssertGreaterThan(bitmap.width, 0)
        XCTAssertGreaterThan(bitmap.height, 0)
        XCTAssertEqual(bitmap.pixels.count, bitmap.width * bitmap.height * 4)

        // At least one pixel must be non-zero since we paint an opaque black
        // background plus spot markers.
        let hasNonZero = bitmap.pixels.contains(where: { $0 != 0 })
        XCTAssertTrue(hasNonZero)
    }

    #if canImport(CoreGraphics)
    func testGenerateMapPreviewReturnsCGImageOnMac() {
        let map = BfmeMap(
            id: "maps/fourplayer.map",
            name: "Four Player",
            game: 1,
            preview: "",
            width: 640,
            height: 480,
            spots: []
        )
        let image = BfmeMapImporter.generateMapPreview(map)
        XCTAssertNotNil(image)
        if let image {
            XCTAssertGreaterThan(image.width, 0)
            XCTAssertGreaterThan(image.height, 0)
        }
    }
    #else
    func testLinuxFallbackReturnsRGBABitmap() {
        let map = BfmeMap(
            id: "maps/fourplayer.map",
            name: "Four Player",
            game: 1,
            preview: "",
            width: 640,
            height: 480,
            spots: []
        )
        let result = BfmeMapImporter.generateMapPreview(map)
        XCTAssertNotNil(result)
        if let result {
            XCTAssertFalse(result.pixels.isEmpty)
        }
    }
    #endif

    func testImportMapsParsesMinimalMapCache() {
        let mapcache = """
        mapcache mymap_4p.map
          isMultiplayer = yes
          isOfficial = yes
          displayName = MAP:FourPlayerMap
          extentMax = X:640.0 Y:480.0
          Player_1_Start = X:100.0 Y:100.0
          Player_2_Start = X:500.0 Y:100.0
          Player_3_Start = X:100.0 Y:400.0
          Player_4_Start = X:500.0 Y:400.0
        end
        """

        let stringTables = [
            """
            MAP:FourPlayerMap
              "Four Player Map"
            END
            """
        ]

        let available: Set<String> = ["mymap_4p.map"]
        let maps = BfmeMapImporter.importMaps(
            fromMapCacheIni: mapcache,
            stringTables: stringTables,
            availableMapIds: available
        )
        XCTAssertEqual(maps.count, 1)
        let map = maps[0]
        XCTAssertEqual(map.id, "mymap_4p.map")
        XCTAssertEqual(map.name, "Four Player Map")
        XCTAssertEqual(map.width, 640)
        XCTAssertEqual(map.height, 480)
        XCTAssertEqual(map.spots.count, 4)
    }

    func testImportMapsDropsNonOfficialOrNonMultiplayer() {
        let mapcache = """
        mapcache skip_me.map
          isMultiplayer = no
          isOfficial = yes
          displayName = Skip
          extentMax = X:100.0 Y:100.0
        end
        mapcache keep_me.map
          isMultiplayer = yes
          isOfficial = yes
          displayName = Keep
          extentMax = X:100.0 Y:100.0
        end
        """
        let maps = BfmeMapImporter.importMaps(
            fromMapCacheIni: mapcache,
            availableMapIds: ["skip_me.map", "keep_me.map"]
        )
        XCTAssertEqual(maps.count, 1)
        XCTAssertEqual(maps[0].id, "keep_me.map")
    }
}
