import Foundation

public enum CsfConverter {
    /// Converts an EA .csf localization payload to the text .str format used
    /// by the BFME tools. First-wins on duplicate label names to match the
    /// original C# behavior.
    public static func convertToStr(_ source: Data) throws -> String {
        if source.isEmpty { return "" }

        var reader = BinaryReader(source)
        _ = try reader.readFixedLengthString(4)  // "CSF "
        _ = try reader.readUInt32LE()            // version
        let nLabels = try reader.readUInt32LE()
        _ = try reader.readUInt32LE()            // n_strings
        _ = try reader.readUInt32LE()            // extra_tag
        _ = try reader.readUInt32LE()            // lang

        var orderedKeys: [String] = []
        var strings: [String: String] = [:]

        for _ in 0..<Int(nLabels) {
            _ = try reader.readFixedLengthString(4)          // "LBL "
            let nPairs = try reader.readUInt32LE()
            let nameLength = try reader.readUInt32LE()
            let name = try reader.readFixedLengthString(Int(nameLength))

            for _ in 0..<Int(nPairs) {
                _ = try reader.readFixedLengthString(4)      // "STR "/"STRW"
                let valueLength = try reader.readUInt32LE()
                let rawValue = try reader.readFixedLengthStringUnicode(Int(valueLength))
                let value = rawValue.replacingOccurrences(of: "\n", with: "\\n")

                if strings[name] == nil {
                    strings[name] = value
                    orderedKeys.append(name)
                }
            }
        }

        var output = ""
        for key in orderedKeys {
            let value = strings[key] ?? ""
            output += "\(key)\n\"\(value)\"\nEND\n\n"
        }
        // The original C# used `string.Join("\n", ...)` so trim trailing
        // whitespace to match the empirical "one trailing newline" shape.
        if output.hasSuffix("\n\n") {
            output.removeLast()
        }
        return output
    }
}
