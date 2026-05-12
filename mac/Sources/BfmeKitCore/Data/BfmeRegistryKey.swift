import Foundation

public enum BfmeRegistryKey: String, Equatable, Hashable, CaseIterable, Sendable {
    case installPath = "InstallPath"
    case language = "Language"
    case mapPackVersion = "MapPackVersion"
    case useLocalUserMaps = "UseLocalUserMaps"
    case userDataLeafName = "UserDataLeafName"
    case version = "Version"
    case serialKey = "SerialKey"
}
