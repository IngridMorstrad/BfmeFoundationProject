import Foundation
import BfmeKitCore

/// Pure text parser for `playertemplate.ini` files that BFME ships inside its
/// `.big` archives. Only `PlayableSide = Yes` blocks are surfaced, and each
/// recognized faction name is mapped to its standard portrait asset.
public enum BfmeFactionImporter {
    public static func importFactions(fromPlayerTemplateIni playerTemplateIni: String) -> [BfmeFaction] {
        var results: [BfmeFaction] = []

        var inBlock = false
        var blockValid = true
        var blockName = ""
        var blockId = 0

        for rawLine in playerTemplateIni.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\n\r \t"))
            if line.isEmpty || line.hasPrefix("//") || line.hasPrefix(";") {
                continue
            }

            let lower = line.lowercased()
            if lower.hasPrefix("playertemplate") {
                inBlock = true
                blockName = line
                    .replacingOccurrences(of: "PlayerTemplate ", with: "")
                    .replacingOccurrences(of: "playerTemplate ", with: "")
                    .replacingOccurrences(of: "playertemplate ", with: "")
            } else if inBlock {
                var safeLine = line.replacingOccurrences(of: "\t", with: "  ")
                while safeLine.contains("  ") {
                    safeLine = safeLine.replacingOccurrences(of: "  ", with: " ")
                }
                safeLine = safeLine.trimmingCharacters(in: CharacterSet(charactersIn: " "))

                let safeLower = safeLine.lowercased()
                if safeLower.hasPrefix("playableside") {
                    blockValid = blockValid && safeLower.contains("playableside = yes")
                }

                if safeLower.hasPrefix("end") {
                    if blockValid {
                        let (big, small) = factionIcons(for: blockName)
                        results.append(
                            BfmeFaction(
                                name: blockName,
                                id: blockId,
                                bigIcon: big,
                                smallIcon: small
                            )
                        )
                    }

                    inBlock = false
                    blockValid = true
                    blockName = ""
                    blockId += 1
                }
            }
        }

        return results
    }

    private static func factionIcons(for blockName: String) -> (String, String) {
        switch blockName {
        case "FactionRohan":    return ("STANDARD:rohan.png", "STANDARD:rohan.png")
        case "FactionGondor":   return ("STANDARD:gondor.png", "STANDARD:gondor.png")
        case "FactionIsengard": return ("STANDARD:isengard.png", "STANDARD:isengard.png")
        case "FactionMordor":   return ("STANDARD:mordor.png", "STANDARD:mordor.png")
        case "FactionMen":      return ("STANDARD:men.png", "STANDARD:men.png")
        case "FactionElves":    return ("STANDARD:elves.png", "STANDARD:elves.png")
        case "FactionDwarves":  return ("STANDARD:dwarves.png", "STANDARD:dwarves.png")
        case "FactionWild":     return ("STANDARD:goblins.png", "STANDARD:goblins.png")
        case "FactionAngmar":   return ("STANDARD:angmar.png", "STANDARD:angmar.png")
        default:                return ("STANDARD:rohan.png", "STANDARD:rohan.png")
        }
    }
}
