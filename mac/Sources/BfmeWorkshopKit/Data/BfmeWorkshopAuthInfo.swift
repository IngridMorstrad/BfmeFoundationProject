import Foundation

/// Mirror of `BfmeWorkshopAuthInfo.cs`. Tuple-style login credentials
/// passed to the Workshop HTTP API via `AuthAccountUuid` +
/// `AuthAccountPassword` headers.
public struct BfmeWorkshopAuthInfo: Codable, Equatable, Hashable, Sendable {
    public var uuid: String
    public var password: String

    public init(uuid: String = "", password: String = "") {
        self.uuid = uuid
        self.password = password
    }

    public init(accountUuid: String, accountPassword: String) {
        self.uuid = accountUuid
        self.password = accountPassword
    }

    public static let unauthenticated = BfmeWorkshopAuthInfo(
        accountUuid: "unauthenticated",
        accountPassword: ""
    )

    enum CodingKeys: String, CodingKey {
        case uuid = "Uuid"
        case password = "Password"
    }
}
