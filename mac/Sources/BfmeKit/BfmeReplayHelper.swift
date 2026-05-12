import Foundation
import BfmeKitCore

/// Resolves the path to BFME replay files. The C# original walked the game's
/// `.str`/`.csf` string tables to find a `GUI:LastReplay` entry; we accept
/// a pre-collected list of string-table bodies and do the same walk in Swift.
public enum BfmeReplayHelper {
    /// Returns the on-disk path that hosts the "last replay" for a given game.
    ///
    /// - Parameters:
    ///   - game: Game id (0 = BFME1, 1 = BFME2, 2 = ROTWK).
    ///   - stringTables: Pre-collected `.str`/`.csf` text from the game's
    ///     `lang/*.big` and mod directory. Pass `[]` to skip the lookup.
    public static func getReplayFilePath(
        game: Int,
        stringTables: [String] = []
    ) async -> String {
        let fm = FileManager.default
        let leafName = await BfmeRegistryManager.getKeyValue(game, .userDataLeafName)
        let replaysRoot = BfmeRegistryManager.applicationDataDirectory(fileManager: fm)
            .appendingPathComponent(leafName, isDirectory: true)
            .appendingPathComponent("Replays", isDirectory: true)

        if game > 0 {
            if await BfmeRegistryManager.isInstalled(game) {
                for table in stringTables {
                    var blockId = ""
                    var blockContent = ""
                    for rawLine in table.split(separator: "\n", omittingEmptySubsequences: false) {
                        let line = String(rawLine).trimmingCharacters(in: CharacterSet(charactersIn: "\n\r \t"))
                        if line.isEmpty || line.hasPrefix("//") || line.hasPrefix(";") { continue }

                        if blockId.isEmpty {
                            blockId = line
                            blockContent = ""
                        } else if line.lowercased().hasPrefix("end") {
                            if blockId.lowercased() == "gui:lastreplay" {
                                let trimmed = blockContent.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                                return replaysRoot
                                    .appendingPathComponent("\(trimmed).BfME2Replay")
                                    .path
                            }
                            blockId = ""
                            blockContent = ""
                        } else {
                            blockContent = line
                        }
                    }
                }
            }
            return replaysRoot.appendingPathComponent("Last Replay.BfME2Replay").path
        } else {
            return replaysRoot.appendingPathComponent("00000000.rep").path
        }
    }
}
