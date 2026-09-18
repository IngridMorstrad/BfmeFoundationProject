import Foundation

/// Reads and writes the state that the Windows BFME executables can actually
/// see, inside the Wine prefix they run in.
///
/// Without this, a native macOS launcher can manage BFME perfectly in its own
/// storage and the games will still report themselves as not installed: they
/// call `RegOpenKeyEx(HKEY_LOCAL_MACHINE, "SOFTWARE\\Electronic Arts\\...")`,
/// which resolves to the prefix's registry, and read `InstallPath` from there.
public struct WinePrefixBridge: Sendable {
    public let runtime: WineRuntime
    private let runner: ProcessRunning
    private let fileManager: FileManager

    public init(runtime: WineRuntime, runner: ProcessRunning = SystemProcessRunner(), fileManager: FileManager = .default) {
        self.runtime = runtime
        self.runner = runner
        self.fileManager = fileManager
    }

    // MARK: - Path translation

    /// Translates a macOS path into the Windows path the game will see.
    ///
    /// Required for every path that gets stored in the registry. A raw POSIX
    /// path like `/Users/me/Games/BFME2` is useless to the game: it appends
    /// `\lotrbfme2ep1.exe` to whatever `InstallPath` holds, so the value has to
    /// already be in Windows form (`Z:\Users\me\Games\BFME2` or, if the folder
    /// sits inside the prefix, `C:\...`).
    public func windowsPath(forUnixPath unixPath: String) throws -> String {
        let result = try runWineTool("winepath", arguments: ["--windows", unixPath])
        let translated = result.trimmedOutput
        guard !translated.isEmpty else {
            throw WineBridgeError.emptyPathTranslation(input: unixPath)
        }
        return translated
    }

    /// Translates a Windows path from inside the prefix back to a macOS path.
    public func unixPath(forWindowsPath windowsPath: String) throws -> String {
        let result = try runWineTool("winepath", arguments: ["--unix", windowsPath])
        let translated = result.trimmedOutput
        guard !translated.isEmpty else {
            throw WineBridgeError.emptyPathTranslation(input: windowsPath)
        }
        return translated
    }

    /// The prefix's `%APPDATA%`, as a macOS path.
    ///
    /// The games read `Options.ini` (resolution, audio) from
    /// `%APPDATA%\My Battle for Middle-earth Files\`. Writing that to the
    /// host's `~/Library/Application Support` puts it somewhere the game will
    /// never look, so the launcher needs the real location on disk.
    public func applicationDataDirectory() throws -> String {
        try unixPath(forWindowsPath: try expandEnvironment("%APPDATA%"))
    }

    /// Expands a Windows environment variable inside the prefix.
    public func expandEnvironment(_ expression: String) throws -> String {
        let result = try runWineTool("cmd", arguments: ["/c", "echo \(expression)"])
        let expanded = result.trimmedOutput
        guard !expanded.isEmpty, expanded != expression else {
            throw WineBridgeError.emptyPathTranslation(input: expression)
        }
        return expanded
    }

    // MARK: - Registry

    /// Imports a document through `regedit /S`.
    ///
    /// `wineserver -w` afterwards waits for the server to go idle, which is
    /// what flushes the change out to `system.reg`. Skipping it risks starting
    /// the game before the values are durable.
    public func importRegistry(_ document: RegistryDocument) throws {
        guard !document.isEmpty else { return }

        let scratchURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bfme-registry-\(UUID().uuidString).reg")

        try document.serializedData().write(to: scratchURL, options: .atomic)
        defer { try? fileManager.removeItem(at: scratchURL) }

        _ = try runWineTool("regedit", arguments: ["/S", scratchURL.path])
        try waitForWineserver()
    }

    /// Reads every value on a key. Returns nil when the key does not exist,
    /// which is the normal "not installed yet" answer rather than an error.
    ///
    /// Deliberately implemented with `regedit /E` rather than `reg query`.
    /// `reg.exe` writes its output in the console's OEM codepage, so a path
    /// containing non-ASCII characters (a macOS account called `José`, say)
    /// comes back as mojibake and any comparison against what was written
    /// fails. `regedit /E` emits a UTF-16LE document, which round trips
    /// exactly. Verified against Wine 11.17.
    public func readValues(hive: RegistryHive, path: String) throws -> [String: RegistryValue]? {
        let exportURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bfme-export-\(UUID().uuidString).reg")
        defer { try? fileManager.removeItem(at: exportURL) }

        let keyPath = "\(hive.rawValue)\\\(path)"
        _ = try? runner.run(
            executable: runtime.binaryPath,
            arguments: ["regedit", "/E", exportURL.path, keyPath],
            environment: runtime.toolEnvironment
        )

        // regedit writes no file at all for a key that does not exist.
        guard let data = try? Data(contentsOf: exportURL) else { return nil }

        return Self.parseExport(data, forKeyPath: keyPath)
    }

    /// Reads one value. The empty name means the key's default value.
    public func readValue(hive: RegistryHive, path: String, name: String) throws -> RegistryValue? {
        try readValues(hive: hive, path: path)?[name]
    }

    /// Convenience string accessor for callers that only care about text.
    public func readStringValue(hive: RegistryHive, path: String, name: String) throws -> String? {
        guard case .string(let value)? = try readValue(hive: hive, path: path, name: name) else { return nil }
        return value
    }

    /// Parses a `.reg` export, returning the values belonging to one exact key.
    ///
    /// An export includes the requested key plus all of its subkeys, so the
    /// section header has to be matched exactly rather than by prefix.
    static func parseExport(_ data: Data, forKeyPath keyPath: String) -> [String: RegistryValue]? {
        guard let text = decodeRegDocument(data) else { return nil }

        var values: [String: RegistryValue] = [:]
        var insideTargetSection = false
        var sawTargetSection = false

        // Must be `isNewline`, not a comparison against "\r"/"\n": Swift treats
        // CRLF as a single grapheme cluster, so neither of those ever matches
        // and the whole document would come through as one line.
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("[") && line.hasSuffix("]") {
                let section = String(line.dropFirst().dropLast())
                insideTargetSection = section.caseInsensitiveCompare(keyPath) == .orderedSame
                if insideTargetSection { sawTargetSection = true }
                continue
            }

            guard insideTargetSection else { continue }

            if let (name, value) = parseValueLine(line) {
                values[name] = value
            }
        }

        return sawTargetSection ? values : nil
    }

    /// `"Name"="text"`, `@="text"`, or `"Name"=dword:0000000f`.
    static func parseValueLine(_ line: String) -> (name: String, value: RegistryValue)? {
        let name: String
        let remainder: Substring

        if line.hasPrefix("@=") {
            name = ""
            remainder = line.dropFirst(2)
        } else {
            guard line.hasPrefix("\"") else { return nil }
            // Find the closing quote of the name, honouring backslash escapes.
            var index = line.index(after: line.startIndex)
            var rawName = ""
            var escaped = false
            while index < line.endIndex {
                let character = line[index]
                if escaped {
                    rawName.append(character)
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    break
                } else {
                    rawName.append(character)
                }
                index = line.index(after: index)
            }
            guard index < line.endIndex else { return nil }
            let afterName = line.index(after: index)
            guard afterName < line.endIndex, line[afterName] == "=" else { return nil }
            name = rawName
            remainder = line[line.index(after: afterName)...]
        }

        if remainder.hasPrefix("dword:") {
            let hex = remainder.dropFirst("dword:".count)
            guard let parsed = UInt32(hex, radix: 16) else { return nil }
            return (name, .dword(parsed))
        }

        guard remainder.hasPrefix("\""), remainder.hasSuffix("\""), remainder.count >= 2 else { return nil }
        let body = remainder.dropFirst().dropLast()
        return (name, .string(unescape(String(body))))
    }

    /// Reverses `RegistryDocument.escape`.
    static func unescape(_ raw: String) -> String {
        var out = ""
        var escaped = false
        for character in raw {
            if escaped {
                out.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                out.append(character)
            }
        }
        return out
    }

    /// Decodes a `.reg` document, honouring the UTF-16LE BOM regedit writes and
    /// falling back to UTF-8 for hand-written files.
    static func decodeRegDocument(_ data: Data) -> String? {
        if data.count >= 2, data[data.startIndex] == 0xFF, data[data.startIndex + 1] == 0xFE {
            return String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
        }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Prefix lifecycle

    /// Creates or updates the prefix. Safe to call repeatedly.
    public func ensurePrefixInitialised() throws {
        if let prefixPath = runtime.prefixPath, !fileManager.fileExists(atPath: prefixPath) {
            try fileManager.createDirectory(atPath: prefixPath, withIntermediateDirectories: true)
        }
        _ = try runWineTool("wineboot", arguments: ["--update"])
        try waitForWineserver()
    }

    /// Blocks until the prefix's wineserver has no more work pending.
    public func waitForWineserver() throws {
        // A missing wineserver next to the wine binary is not fatal: the
        // registry import already succeeded, we just cannot force the flush.
        let serverPath = URL(fileURLWithPath: runtime.binaryPath)
            .deletingLastPathComponent()
            .appendingPathComponent("wineserver")
            .path
        guard fileManager.isExecutableFile(atPath: serverPath) else { return }

        _ = try? runner.run(
            executable: serverPath,
            arguments: ["-w"],
            environment: runtime.toolEnvironment
        )
    }

    // MARK: - Internals

    @discardableResult
    private func runWineTool(_ tool: String, arguments: [String]) throws -> ProcessResult {
        let result = try runner.run(
            executable: runtime.binaryPath,
            arguments: [tool] + arguments,
            environment: runtime.toolEnvironment
        )

        guard result.succeeded else {
            throw WineBridgeError.toolFailed(
                tool: tool,
                exitCode: result.exitCode,
                message: result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return result
    }
}
