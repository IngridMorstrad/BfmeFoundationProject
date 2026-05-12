import Foundation
import BfmeKitCore

/// Reads and writes the BFME `Options.ini` file that lives under the game's
/// UserData leaf directory. The C# original keyed off
/// `Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData)`;
/// on macOS we reroute to `~/Library/Application Support` via
/// `BfmeRegistryManager.applicationDataDirectory`.
public enum BfmeSettingsManager {
    /// Returns the value for `optionName` from the game's `Options.ini`,
    /// or `nil` if either the file or the option is missing.
    public static func get(_ game: Int, _ optionName: String) async -> String? {
        let url = await optionsFileURL(for: game)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        let table = parse(text)
        return table[optionName]
    }

    /// Upserts an option in the `Options.ini`. Writes the default options
    /// template to the file first if it does not yet exist. The output is
    /// a stable alphabetically-sorted list so two consecutive calls produce
    /// byte-identical output.
    public static func set(_ game: Int, _ optionName: String, _ value: String) async throws {
        let url = await optionsFileURL(for: game)
        let fm = FileManager.default
        let directory = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let sourceText: String
        if let existing = try? String(contentsOf: url, encoding: .utf8) {
            sourceText = existing
        } else {
            sourceText = BfmeDefaults.defaultOptions
        }

        var table = parse(sourceText)
        table[optionName] = value

        let serialized = table
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key) = \($0.value)" }
            .joined(separator: "\n")
        try serialized.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Helpers

    static func optionsFileURL(for game: Int) async -> URL {
        let leaf = await BfmeRegistryManager.getKeyValue(game, .userDataLeafName)
        let appData = BfmeRegistryManager.applicationDataDirectory()
        return appData
            .appendingPathComponent(leaf, isDirectory: true)
            .appendingPathComponent("Options.ini")
    }

    static func parse(_ text: String) -> [String: String] {
        var table: [String: String] = [:]
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine).trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            guard let range = line.range(of: " = ") else { continue }
            let key = String(line[..<range.lowerBound])
            let value = String(line[range.upperBound...])
            table[key] = value
        }
        return table
    }
}
