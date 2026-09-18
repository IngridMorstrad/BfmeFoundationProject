import Foundation

/// A registry hive, spelled the way a `.reg` file spells it.
public enum RegistryHive: String, Sendable, Hashable {
    case localMachine = "HKEY_LOCAL_MACHINE"
    case currentUser = "HKEY_CURRENT_USER"

    /// Short form accepted by `reg.exe`.
    public var shortName: String {
        switch self {
        case .localMachine: return "HKLM"
        case .currentUser: return "HKCU"
        }
    }
}

/// A value to write. Only the two types the BFME tree actually uses.
public enum RegistryValue: Equatable, Sendable {
    case string(String)
    case dword(UInt32)

    /// `.reg` right-hand side for this value.
    var regLiteral: String {
        switch self {
        case .string(let raw):
            return "\"\(RegistryDocument.escape(raw))\""
        case .dword(let value):
            return String(format: "dword:%08x", value)
        }
    }
}

/// One key plus the values to set on it.
public struct RegistryKeyEntry: Equatable, Sendable {
    public let hive: RegistryHive
    /// Path below the hive, backslash separated, no leading backslash.
    public let path: String
    /// Value name to value. The empty name is the key's default value.
    public let values: [(name: String, value: RegistryValue)]

    public init(hive: RegistryHive, path: String, values: [(name: String, value: RegistryValue)]) {
        self.hive = hive
        self.path = path
        self.values = values
    }

    public static func == (lhs: RegistryKeyEntry, rhs: RegistryKeyEntry) -> Bool {
        lhs.hive == rhs.hive
            && lhs.path == rhs.path
            && lhs.values.count == rhs.values.count
            && zip(lhs.values, rhs.values).allSatisfy { $0.name == $1.name && $0.value == $1.value }
    }

    public var fullPath: String { "\(hive.rawValue)\\\(path)" }
}

/// Builds a `.reg` file for import through `regedit`.
///
/// Writing the prefix's `system.reg` directly would be a mistake: a running
/// `wineserver` holds the registry in memory and rewrites those files on its
/// own schedule, so an external edit is liable to be silently discarded. Going
/// through `regedit` means Wine's own registry code does the write, which is
/// both correct and durable.
public struct RegistryDocument: Equatable, Sendable {
    public private(set) var entries: [RegistryKeyEntry]

    public init(entries: [RegistryKeyEntry] = []) {
        self.entries = entries
    }

    public mutating func add(_ entry: RegistryKeyEntry) {
        entries.append(entry)
    }

    public var isEmpty: Bool { entries.isEmpty }

    /// The textual `.reg` content.
    ///
    /// `REGEDIT4` vs `Version 5.00` matters: version 5 is the Unicode format,
    /// which is what lets a path containing non-ASCII characters (a macOS
    /// account name with an accent, say) survive the round trip.
    public func serialize() -> String {
        var lines: [String] = ["Windows Registry Editor Version 5.00", ""]

        for entry in entries {
            lines.append("[\(entry.fullPath)]")
            for (name, value) in entry.values {
                if name.isEmpty {
                    lines.append("@=\(value.regLiteral)")
                } else {
                    lines.append("\"\(Self.escape(name))\"=\(value.regLiteral)")
                }
            }
            lines.append("")
        }

        // .reg files are CRLF terminated.
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// UTF-16LE with a byte order mark, the canonical encoding for a
    /// "Version 5.00" file. Wine's regedit also tolerates UTF-8, but emitting
    /// the documented encoding avoids depending on that leniency.
    public func serializedData() -> Data {
        var data = Data([0xFF, 0xFE])
        let text = serialize()
        for unit in Array(text.utf16) {
            data.append(UInt8(unit & 0xFF))
            data.append(UInt8(unit >> 8))
        }
        return data
    }

    /// Escapes a string for use inside `.reg` double quotes. Backslash first,
    /// or the quote escape's own backslash would be double escaped.
    static func escape(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\", with: "\\\\")
           .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
