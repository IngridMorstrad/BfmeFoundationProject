import Foundation
@_exported import BfmeKitCore

/// Umbrella module for BfmeKit. Re-exports the portable `BfmeKitCore` surface
/// and hosts the macOS-native managers (registry shim, settings I/O, importers,
/// replay helper, map preview compositor) ported from the Windows C# tree.
public enum BfmeKit {
    public static let moduleVersion = "0.2.0"
}
