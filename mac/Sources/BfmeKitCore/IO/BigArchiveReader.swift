import Foundation

public enum BigArchiveReaderError: Error {
    case readFailed(String)
}

public enum BigArchiveReader {
    /// Parses the index table of an EA .big archive and returns a dictionary
    /// keyed by lowercase entry name.
    ///
    /// Mirrors the original C# reader's behavior: first-wins on duplicate
    /// names, and a `throwOnError=false` swallow that returns an empty
    /// dictionary if anything goes wrong mid-parse.
    public static func unpack(_ sourceBigArchive: String, throwOnError: Bool = false) throws -> [String: BigFile] {
        var files: [String: BigFile] = [:]

        let url = URL(fileURLWithPath: sourceBigArchive)
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            if throwOnError { throw error }
            return [:]
        }

        guard !data.isEmpty else { return files }

        do {
            var reader = BinaryReader(data)
            _ = try reader.readFixedLengthString(4)      // id ("BIGF"/"BIG4"/...)
            _ = try reader.readUInt32LE()                // file_size (little-endian)
            let nFiles = try reader.readUInt32BE()
            _ = try reader.readUInt32BE()                // index_table_size

            for _ in 0..<Int(nFiles) {
                let embeddedOffset = try reader.readUInt32BE()
                let embeddedSize = try reader.readUInt32BE()
                let embeddedName = try reader.readNullTerminatedString().lowercased()

                if files[embeddedName] == nil {
                    files[embeddedName] = BigFile(
                        name: embeddedName,
                        source: sourceBigArchive,
                        offset: Int(embeddedOffset),
                        size: Int(embeddedSize)
                    )
                }
            }
        } catch {
            if throwOnError { throw error }
            return [:]
        }

        return files
    }

    /// Decodes the BFME escape-sequence filename encoding used in workshop
    /// payloads (e.g. `_5C` -> `\`, `_3A` -> `:`).
    public static func decodeString(_ str: String) -> String {
        var result = str
        let replacements: [(String, String)] = [
            ("_5C", #"\"#),
            ("_3A", ":"),
            ("_2E", "."),
            ("_20", " "),
            ("_24", "$"),
            ("_00", ""),
            ("_5F", "_"),
            ("_2D", "-"),
            ("_28", "("),
            ("_29", ")"),
            ("_5B", "["),
            ("_5D", "]"),
            ("_21", "!"),
            ("_27", "'")
        ]
        for (token, replacement) in replacements {
            result = result.replacingOccurrences(of: token, with: replacement)
        }
        return result
    }
}
