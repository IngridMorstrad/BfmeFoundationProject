import Foundation

/// Direct port of `src/BfmeFoundationProject_AllInOneLauncher/Data/Consts.cs`.
/// URLs are identical; the Windows "-main" suffix is preserved because the
/// backend doesn't care about the host OS — it just serves the launcher
/// binary/version string.
public enum Consts {
    public static let latestVersionSourceURL = "https://bfmeladder.com/api/applications/versionHash?name=all-in-one-launcher&version=main"
    public static let latestBuildSourceURL = "https://arena-files.bfmeladder.com/application-builds/all-in-one-launcher-main"
}
