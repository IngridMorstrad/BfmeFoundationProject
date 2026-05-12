import Foundation
@_exported import BfmeKitCore

/// Umbrella module for BfmeKit. Subsequent features layer platform-specific
/// logic (registry shims, launcher managers, importers) on top of the
/// portable `BfmeKitCore` surface re-exported here.
public enum BfmeKit {
    public static let moduleVersion = "0.1.0"
}
