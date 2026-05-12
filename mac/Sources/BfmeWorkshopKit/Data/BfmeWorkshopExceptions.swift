import Foundation

/// Mirror of `BfmeWorkshopExceptions.cs`: one Swift error case per C#
/// exception class so call-sites can `catch` them with the same intent.
public enum BfmeWorkshopError: Error, Equatable, CustomStringConvertible {
    case packageNotSyncable(String)
    case gameNotInstalled(String)
    case enhancementIncompatible(String)
    case fileMissing(String)
    case entryNotFound(String)
    case scriptMissingRequirements(String)
    case scriptSyntaxError(String)

    public var description: String {
        switch self {
        case .packageNotSyncable(let m),
             .gameNotInstalled(let m),
             .enhancementIncompatible(let m),
             .fileMissing(let m),
             .entryNotFound(let m),
             .scriptMissingRequirements(let m),
             .scriptSyntaxError(let m):
            return m
        }
    }
}
