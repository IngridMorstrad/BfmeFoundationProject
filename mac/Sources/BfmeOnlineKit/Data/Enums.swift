import Foundation

/// Mirror of `OnlineKit/Data/Enums.cs`. Visual state the online page walks
/// through while staging the arena process.
public enum OnlineMenuVisualState: String, Codable, Sendable {
    case designerMode
    case unloaded
    case checkingForUpdates
    case loading
    case downloadProgress
    case updateProgress
    case repairProgress
    case loaded
    case serverDown
}
