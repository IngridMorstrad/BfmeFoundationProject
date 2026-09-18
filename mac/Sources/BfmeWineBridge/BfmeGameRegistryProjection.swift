import Foundation
import BfmeKitCore

/// The launcher-side state for one game that the Windows executable needs to
/// find in the registry.
///
/// `installPathUnix` is deliberately a macOS path: that is the launcher's own
/// canonical representation, because the launcher does real file work on it
/// (copying Workshop content, hard linking, checking existence). Translation to
/// a Windows path happens once, here, at the boundary.
public struct BfmeGameRegistryState: Equatable, Sendable {
    public let game: Int
    public let installPathUnix: String
    public let language: String
    public let serialKey: String
    public let version: UInt32
    public let mapPackVersion: UInt32
    public let useLocalUserMaps: UInt32
    public let userDataLeafName: String

    public init(
        game: Int,
        installPathUnix: String,
        language: String,
        serialKey: String,
        version: UInt32 = 65539,
        mapPackVersion: UInt32 = 65536,
        useLocalUserMaps: UInt32 = 0,
        userDataLeafName: String? = nil
    ) {
        self.game = game
        self.installPathUnix = installPathUnix
        self.language = language
        self.serialKey = serialKey
        self.version = version
        self.mapPackVersion = mapPackVersion
        self.useLocalUserMaps = useLocalUserMaps
        self.userDataLeafName = userDataLeafName ?? BfmeDefaults.defaultUserDataLeafNames[game] ?? ""
    }
}

/// Turns launcher state into the registry writes the games read.
public enum BfmeGameRegistryProjection {
    /// Builds the document to import into the prefix.
    ///
    /// Each key is written twice, under `SOFTWARE\...` and
    /// `SOFTWARE\WOW6432Node\...`, on purpose. The BFME executables are 32-bit:
    ///
    ///  - In a 64-bit prefix, a 32-bit process asking for `SOFTWARE\X` is
    ///    redirected by WOW64 to `SOFTWARE\WOW6432Node\X`, so only the
    ///    WOW6432Node copy is visible to the game.
    ///  - In a 32-bit prefix there is no redirector and no WOW6432Node at all,
    ///    so only the plain copy exists.
    ///
    /// Writing both makes the projection correct without having to detect the
    /// prefix architecture, at the cost of a few redundant values.
    public static func document(
        for state: BfmeGameRegistryState,
        installPathWindows: String
    ) -> RegistryDocument {
        var document = RegistryDocument()

        let gameKey = BfmeDefaults.defaultGameRegistryKeys[state.game] ?? ""
        let executable = BfmeDefaults.defaultGameExecutableNames[state.game] ?? ""

        // The games expect InstallPath to carry a trailing separator; they
        // concatenate rather than join.
        let normalizedInstallPath = installPathWindows.hasSuffix("\\")
            ? installPathWindows
            : installPathWindows + "\\"

        for softwareRoot in softwareRoots {
            let base = "\(softwareRoot)\\\(gameKey)"

            document.add(RegistryKeyEntry(hive: .localMachine, path: base, values: [
                (name: "InstallPath", value: .string(normalizedInstallPath)),
                (name: "Language", value: .string(state.language)),
                (name: "MapPackVersion", value: .dword(state.mapPackVersion)),
                (name: "UseLocalUserMaps", value: .dword(state.useLocalUserMaps)),
                (name: "UserDataLeafName", value: .string(state.userDataLeafName)),
                (name: "Version", value: .dword(state.version))
            ]))

            // The serial lives in an `ergc` subkey as that key's default value.
            document.add(RegistryKeyEntry(hive: .localMachine, path: "\(base)\\ergc", values: [
                (name: "", value: .string(state.serialKey))
            ]))

            // App Paths is how the game and its patchers resolve the executable
            // by name rather than by full path.
            let appPaths = "\(softwareRoot)\\Microsoft\\Windows\\CurrentVersion\\App Paths\\\(executable)"
            document.add(RegistryKeyEntry(hive: .localMachine, path: appPaths, values: [
                (name: "", value: .string(normalizedInstallPath + executable)),
                (name: "Game Registry", value: .string("\(softwareRoot)\\\(gameKey)")),
                (name: "Installed", value: .dword(1)),
                (name: "Path", value: .string(normalizedInstallPath)),
                (name: "Restart", value: .dword(0))
            ]))
        }

        return document
    }

    /// `SOFTWARE` and `SOFTWARE\WOW6432Node`, in that order.
    static let softwareRoots = ["SOFTWARE", #"SOFTWARE\WOW6432Node"#]

    /// Projects state into the prefix: translate the path, build the document,
    /// import it. Returns the Windows path that was written, so the caller can
    /// log or verify it.
    @discardableResult
    public static func project(
        _ state: BfmeGameRegistryState,
        through bridge: WinePrefixBridge
    ) throws -> String {
        let installPathWindows = try bridge.windowsPath(forUnixPath: state.installPathUnix)
        let document = document(for: state, installPathWindows: installPathWindows)
        try bridge.importRegistry(document)
        return installPathWindows
    }

    /// Reads `InstallPath` back the way the game will see it.
    ///
    /// Reads the `WOW6432Node` copy first. That is not a heuristic: WOW64
    /// redirects a 32-bit process asking for `SOFTWARE\X` to
    /// `SOFTWARE\WOW6432Node\X`, so reading that key explicitly is exactly
    /// equivalent to the read the 32-bit game performs, and it avoids needing a
    /// 32-bit helper process to ask on the game's behalf.
    public static func installedPathAsGameSeesIt(
        game: Int,
        through bridge: WinePrefixBridge
    ) throws -> String? {
        let gameKey = BfmeDefaults.defaultGameRegistryKeys[game] ?? ""
        for root in softwareRoots.reversed() {
            if let value = try bridge.readStringValue(
                hive: .localMachine,
                path: "\(root)\\\(gameKey)",
                name: "InstallPath"
            ), !value.isEmpty {
                return value
            }
        }
        return nil
    }
}
