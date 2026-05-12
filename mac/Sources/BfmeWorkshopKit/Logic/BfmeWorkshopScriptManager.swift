import Foundation
import BfmeHttpInstruments
import BfmeKit
import BfmeKitCore

/// Port of `BfmeWorkshopScriptManager.cs`. Evaluates a .wps DSL script that
/// lets workshop authors gate installation on registry values or file
/// contents, bind those values to named variables, and report
/// `require ... if ...` assertions.
///
/// Example (matches the Windows semantics):
/// ```
/// let InstallPath be InstallPath from HKLM\SOFTWARE\Electronic Arts\EA Games\The Battle for Middle-earth
/// let All be all from HKLM\SOFTWARE\Electronic Arts\EA Games\The Battle for Middle-earth
/// require "HasInstall" if "{InstallPath}" !equals ""
/// ```
///
/// The registry source selector (`HKLM\...`) goes through the new
/// `BfmeRegistryManager` / `RegistryStore` instead of the Win32 registry API.
public enum BfmeWorkshopScriptManager {
    public struct RunResult: Equatable, Sendable {
        public var requirements: [String: Bool]
        public var filesDirectory: String
        public var variables: [String: String]

        public init(requirements: [String: Bool] = [:], filesDirectory: String = "", variables: [String: String] = [:]) {
            self.requirements = requirements
            self.filesDirectory = filesDirectory
            self.variables = variables
        }
    }

    /// Runs the `package.wps` file attached to `entry` if the entry is a
    /// mod (type 1). Returns an empty result otherwise. Fetches the script
    /// via `HttpMarshal.getString` when the URL is http(s); otherwise the
    /// script is expected to exist on disk at the file URL.
    public static func runIfScripted(_ entry: BfmeWorkshopEntry) async throws -> RunResult {
        guard entry.type == 1,
              let script = entry.files.first(where: { $0.name == "package.wps" }) else {
            return RunResult()
        }
        let source: String
        if script.url.hasPrefix("http") {
            source = try await HttpMarshal.getString(url: script.url, headers: [:])
        } else {
            source = FileUtils.readText(path: script.url, default: "")
        }
        return try await run(source)
    }

    /// Evaluates the script `source` and returns the bound variables,
    /// requirements, and files-directory override.
    public static func run(_ source: String) async throws -> RunResult {
        var variables: [String: String] = [:]
        var requirements: [String: Bool] = [:]
        var filesDirectory = ""
        var lineNumber = 0

        for rawLine in source.replacingOccurrences(of: "\r", with: "").split(separator: "\n", omittingEmptySubsequences: false) {
            lineNumber += 1
            let line = String(rawLine)
            if line.hasPrefix("//") { continue }

            let tokens: [String]
            do {
                tokens = try tokenize(line, variables: variables)
            } catch let error as BfmeWorkshopError {
                if case .scriptSyntaxError(let msg) = error {
                    throw BfmeWorkshopError.scriptSyntaxError("Syntax error on line \(lineNumber). \(msg)")
                }
                throw error
            }
            if tokens.isEmpty { continue }

            do {
                switch tokens[0] {
                case "require":
                    let name = try verifyToken(tokens, index: 1, expected: "requirement name")
                    try enforceKeyword(tokens, index: 2, keyword: "if")
                    let lhs = try verifyToken(tokens, index: 3, expected: "requirement comparison left hand side expression")
                    let op  = try verifyToken(tokens, index: 4, expected: "requirement comparison mode")
                    let rhs = try verifyToken(tokens, index: 5, expected: "requirement comparison right hand side expression")
                    let passed: Bool
                    switch op {
                    case "equals":    passed = lhs == rhs
                    case "!equals":   passed = lhs != rhs
                    case "contains":  passed = lhs.contains(rhs)
                    case "!contains": passed = !lhs.contains(rhs)
                    default:
                        throw BfmeWorkshopError.scriptSyntaxError("Invalid requirement comparison mode.")
                    }
                    // Matches the odd double-negative the C# version ships:
                    // a `require` line whose comparison passes does *not*
                    // mark the requirement "satisfied"; the flag records
                    // the "needs action" state instead.
                    let anyOutstanding = requirements.contains { !$0.value }
                    requirements[name] = !passed && !anyOutstanding
                case "files":
                    try enforceKeyword(tokens, index: 1, keyword: "be")
                    try enforceKeyword(tokens, index: 2, keyword: "from")
                    filesDirectory = try verifyToken(tokens, index: 3, expected: "files source expression")
                case "let":
                    let name = try verifyToken(tokens, index: 1, expected: "variable name")
                    try enforceKeyword(tokens, index: 2, keyword: "be")
                    var value = ""
                    if tokens.count > 4 {
                        let selector = try verifyToken(tokens, index: 3, expected: "variable value expression key selector")
                        try enforceKeyword(tokens, index: 4, keyword: "from")
                        let sourceExpr = try verifyToken(tokens, index: 5, expected: "variable value expression source selector")
                        value = await resolveSource(selector: selector, source: sourceExpr)
                    } else {
                        value = try verifyToken(tokens, index: 3, expected: "variable value expression")
                    }
                    variables[name] = value
                case "print":
                    let text = try verifyToken(tokens, index: 1, expected: "print expression")
                    Swift.print("PRINT: '\(text)'")
                default:
                    continue
                }
            } catch let error as BfmeWorkshopError {
                if case .scriptSyntaxError(let msg) = error {
                    throw BfmeWorkshopError.scriptSyntaxError("Syntax error on line \(lineNumber). \(msg)")
                }
                throw error
            }
        }

        return RunResult(requirements: requirements, filesDirectory: filesDirectory, variables: variables)
    }

    // MARK: - Source resolution

    static func resolveSource(selector: String, source: String) async -> String {
        if source.hasPrefix(#"HKLM\"#) {
            let trimmed = String(source.dropFirst(5))
            // Match the C# "SOFTWARE\WOW6432Node\..." rewrite on 64-bit hosts
            // (see review bullet #6). On Windows the registry redirector
            // silently transparently routes SOFTWARE\EA GAMES and SOFTWARE\
            // Electronic Arts writes to the WOW6432Node hive, and BFME (a
            // 32-bit process) reads from the same redirected view. We mirror
            // that by rewriting `SOFTWARE\` only when:
            //   1. The path does not already contain a WOW6432Node segment
            //      (otherwise we double-prefix to
            //      SOFTWARE\WOW6432Node\WOW6432Node\...).
            //   2. The path is not rooted at the deprecated `EA GAMES` hive.
            //      `ensureFixedRegistry` reads the legacy pre-redirect keys
            //      under `SOFTWARE\EA GAMES\...` directly, so the rewrite
            //      would miss that data entirely.
            let alreadyRedirected = trimmed.range(of: #"\WOW6432Node\"#) != nil
                || trimmed.hasPrefix(#"SOFTWARE\WOW6432Node\"#)
            let isDeprecatedEAGames = trimmed.hasPrefix(#"SOFTWARE\EA GAMES\"#)
            let canonical: String
            if alreadyRedirected || isDeprecatedEAGames {
                canonical = trimmed
            } else {
                canonical = trimmed.replacingOccurrences(
                    of: #"SOFTWARE\"#,
                    with: #"SOFTWARE\WOW6432Node\"#
                )
            }

            if selector == "all" {
                let names = await RegistryStore.shared.valueNames(hive: .hklm, path: canonical)
                var pairs: [String] = []
                for name in names.sorted() {
                    if let v = await RegistryStore.shared.getValue(hive: .hklm, path: canonical, name: name) {
                        pairs.append("\(name) = \(v.stringValue)")
                    }
                }
                return pairs.joined(separator: "\n")
            }

            if let v = await RegistryStore.shared.getValue(hive: .hklm, path: canonical, name: selector) {
                return v.stringValue
            }
            return ""
        }

        // Absolute-path sources (Windows `X:\` / POSIX `/`) are read from disk.
        if source.contains(#":\"#) || source.hasPrefix("/") {
            if selector == "all" {
                return FileUtils.readText(path: source, default: "")
            }
            let raw = FileUtils.readText(path: source, default: "")
            if source.hasSuffix(".ini") {
                var dict: [String: String] = [:]
                for ln in raw.split(separator: "\n") {
                    let parts = ln.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    guard parts.count == 2 else { continue }
                    let key = parts[0].trimmingCharacters(in: .whitespaces)
                    let value = parts[1].trimmingCharacters(in: .whitespaces)
                    dict[key] = value
                }
                return dict[selector] ?? ""
            }
            if source.hasSuffix(".json") {
                guard let data = raw.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return ""
                }
                if let s = obj[selector] as? String { return s }
                if let n = obj[selector] as? NSNumber { return n.stringValue }
                return ""
            }
            return raw
        }

        return ""
    }

    // MARK: - Tokenizer

    static func tokenize(_ line: String, variables: [String: String]) throws -> [String] {
        var tokens: [String] = []
        var token = ""
        for c in line {
            token.append(c)
            if token.count <= 1 { continue }
            if token.hasPrefix("\"") {
                if c == "\"" {
                    var interpolated = token
                    for (k, v) in variables {
                        interpolated = interpolated.replacingOccurrences(of: "{\(k)}", with: v)
                    }
                    tokens.append(String(interpolated.dropFirst().dropLast()))
                    token = ""
                }
            } else if c == " " {
                let trimmed = token.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { tokens.append(trimmed) }
                token = ""
            }
        }
        if token.hasPrefix("\"") {
            throw BfmeWorkshopError.scriptSyntaxError("String terminator expected.")
        }
        let trimmed = token.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { tokens.append(trimmed) }
        return tokens
    }

    static func verifyToken(_ tokens: [String], index: Int, expected: String) throws -> String {
        if tokens.count > index { return tokens[index] }
        throw BfmeWorkshopError.scriptSyntaxError("Expected '\(expected)' missing.")
    }

    static func enforceKeyword(_ tokens: [String], index: Int, keyword: String) throws {
        if tokens.count <= index || tokens[index] != keyword {
            throw BfmeWorkshopError.scriptSyntaxError("Expected '\(keyword)' keyword missing.")
        }
    }
}
