import Foundation

/// Identifies the Wine installation and prefix that the BFME games will
/// actually run inside.
///
/// This is the whole reason the module exists. The launcher is a native macOS
/// app, but `lotrbfme.exe`, `lotrbfme2.exe` and `lotrbfme2ep1.exe` are closed
/// source 2004-2006 Windows binaries that cannot be rebuilt, so they run under
/// Wine. Anything those binaries need to *see* — registry values, `Options.ini`
/// — has to exist inside this prefix, not in a macOS-native location.
public struct WineRuntime: Equatable, Sendable {
    /// The `wine` / `wine64` binary to invoke.
    public let binaryPath: String

    /// The prefix directory (`WINEPREFIX`). Nil means "whatever the binary
    /// defaults to", which is how CrossOver's bundled wine is normally driven.
    public let prefixPath: String?

    /// Extra environment the compatibility layer needs, e.g. `CX_BOTTLE` for
    /// CrossOver or the Metal translation switches for GPTK.
    public let extraEnvironment: [String: String]

    public init(binaryPath: String, prefixPath: String? = nil, extraEnvironment: [String: String] = [:]) {
        self.binaryPath = binaryPath
        self.prefixPath = prefixPath
        self.extraEnvironment = extraEnvironment
    }

    /// Environment for invoking the Wine tools.
    ///
    /// `WINEDEBUG=-all` keeps Wine's fixme/err chatter out of stdout, which
    /// matters because `winepath`'s output *is* the return value of a path
    /// translation. `WINEDLLOVERRIDES` suppresses the Mono/Gecko installer
    /// dialogs that otherwise block a headless prefix update.
    public var toolEnvironment: [String: String] {
        var environment = extraEnvironment
        if let prefixPath {
            environment["WINEPREFIX"] = prefixPath
        }
        environment["WINEDEBUG"] = environment["WINEDEBUG"] ?? "-all"
        environment["WINEDLLOVERRIDES"] = environment["WINEDLLOVERRIDES"] ?? "mscoree,mshtml="
        return environment
    }
}

public enum WineBridgeError: Error, Equatable, CustomStringConvertible {
    case toolFailed(tool: String, exitCode: Int32, message: String)
    case emptyPathTranslation(input: String)
    case valueNotFound(path: String, name: String)
    case malformedQueryOutput(String)

    public var description: String {
        switch self {
        case .toolFailed(let tool, let exitCode, let message):
            return "wine \(tool) failed with exit code \(exitCode): \(message)"
        case .emptyPathTranslation(let input):
            return "winepath returned nothing when translating '\(input)'. The prefix may not be initialised yet."
        case .valueNotFound(let path, let name):
            return "registry value '\(name)' not found under \(path)"
        case .malformedQueryOutput(let output):
            return "could not parse `reg query` output: \(output)"
        }
    }
}
