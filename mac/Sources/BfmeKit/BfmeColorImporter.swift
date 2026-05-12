import Foundation
import BfmeKitCore

/// Pure text parser for the `multiplayer.ini` color tables that BFME ships
/// inside its `.big` archives. The C# original reached for
/// `System.Drawing.Color`; we translate to `RGBA` / `BfmeColor` instead.
public enum BfmeColorImporter {
    /// Parses a `multiplayer.ini` source string and returns every
    /// `MultiplayerColor` block as a `BfmeColor`.
    public static func importColors(fromMultiplayerIni multiplayerIni: String) -> [BfmeColor] {
        var results: [BfmeColor] = []

        var inBlock = false
        var blockName = ""
        var blockId = 0
        var blockContent = ""

        for rawLine in multiplayerIni.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\n\r \t"))
            if line.isEmpty || line.hasPrefix("//") || line.hasPrefix(";") {
                continue
            }

            let lower = line.lowercased()
            if lower.hasPrefix("multiplayercolor") {
                inBlock = true
                blockName = line
                    .replacingOccurrences(of: "MultiplayerColor ", with: "")
                    .replacingOccurrences(of: "multiplayerColor ", with: "")
                    .replacingOccurrences(of: "multiplayercolor ", with: "")
            } else if inBlock {
                var safeLine = line.replacingOccurrences(of: "\t", with: "  ")
                while safeLine.contains("  ") {
                    safeLine = safeLine.replacingOccurrences(of: "  ", with: " ")
                }
                safeLine = safeLine.trimmingCharacters(in: CharacterSet(charactersIn: " "))

                let safeLower = safeLine.lowercased()
                if safeLower.hasPrefix("rgbcolor") {
                    blockContent = safeLower
                        .replacingOccurrences(of: "rgbcolor =", with: "")
                        .replacingOccurrences(of: "rgbcolor= ", with: "")
                        .trimmingCharacters(in: CharacterSet(charactersIn: " "))
                }

                if safeLower.hasPrefix("end") {
                    let parts = blockContent
                        .split(whereSeparator: { $0 == " " || $0 == ";" })
                        .map(String.init)
                    if parts.count >= 3,
                       let r = Int(parts[0].replacingOccurrences(of: "r:", with: "")),
                       let g = Int(parts[1].replacingOccurrences(of: "g:", with: "")),
                       let b = Int(parts[2].replacingOccurrences(of: "b:", with: "")) {
                        let cleanedName: String
                        if blockName.hasPrefix("Color") {
                            cleanedName = String(blockName.dropFirst("Color".count))
                        } else {
                            cleanedName = blockName
                        }
                        results.append(
                            BfmeColor(
                                name: cleanedName,
                                id: blockId,
                                previewColor: RGBA(
                                    r: UInt8(clamping: r),
                                    g: UInt8(clamping: g),
                                    b: UInt8(clamping: b),
                                    a: 255
                                )
                            )
                        )
                    }

                    inBlock = false
                    blockName = ""
                    blockId += 1
                    blockContent = ""
                }
            }
        }

        return results
    }
}
