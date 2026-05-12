import Foundation

/// Port of `BfmeWorkshopAdminManager.cs`. Everything here requires a valid
/// admin auth tuple; callers must have completed
/// `BfmeWorkshopAuthManager.authenticate` first.
public enum BfmeWorkshopAdminManager {
    /// Publishes a workshop entry. On success the backend echoes the
    /// canonicalized entry which we decode and return; any other body is
    /// surfaced as an `entryNotFound` error (matching the C# fall-through).
    public static func publish(
        authInfo: BfmeWorkshopAuthInfo,
        entry: BfmeWorkshopEntry
    ) async throws -> BfmeWorkshopEntry {
        let encoder = JSONEncoder()
        let data = try encoder.encode(entry)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw BfmeWorkshopError.entryNotFound("Entry could not be JSON-encoded")
        }
        let response = try await HttpUtils.setString(
            authInfo: authInfo,
            apiEndpointPath: "workshop",
            data: jsonString
        )
        guard response.hasPrefix("{"),
              let respData = response.data(using: .utf8) else {
            throw BfmeWorkshopError.entryNotFound(response)
        }
        return try JSONDecoder().decode(BfmeWorkshopEntry.self, from: respData)
    }

    /// Hands an entry over to another account. The server echoes the GUID
    /// (as a JSON-encoded string) on success; anything else is an error.
    public static func transfer(
        authInfo: BfmeWorkshopAuthInfo,
        entryGuid: String,
        newOwner: String
    ) async throws {
        let response = try await HttpUtils.getString(
            authInfo: authInfo,
            apiEndpointPath: "workshop/transfer",
            parameters: ["guid": entryGuid, "newOwner": newOwner]
        )
        let expected: String
        if let data = try? JSONEncoder().encode(entryGuid),
           let s = String(data: data, encoding: .utf8) {
            expected = s
        } else {
            expected = "\"\(entryGuid)\""
        }
        if response != expected {
            throw BfmeWorkshopError.entryNotFound(response)
        }
    }

    public static func unlist(
        authInfo: BfmeWorkshopAuthInfo,
        entryGuid: String
    ) async throws {
        let response = try await HttpUtils.delete(
            authInfo: authInfo,
            apiEndpointPath: "workshop",
            id: entryGuid
        )
        if !response.isEmpty {
            throw BfmeWorkshopError.entryNotFound(response)
        }
    }

    public static func uploadFile(
        authInfo: BfmeWorkshopAuthInfo,
        fileName: String,
        source: String,
        onProgressUpdate: (@Sendable (Int) -> Void)? = nil
    ) async throws {
        try await HttpUtils.upload(
            authInfo: authInfo,
            source: source,
            id: fileName,
            onProgressUpdate: onProgressUpdate
        )
    }

    public static func deleteFiles(
        authInfo: BfmeWorkshopAuthInfo,
        fileNames: [String]
    ) async throws {
        try await HttpUtils.deleteFiles(authInfo: authInfo, ids: fileNames)
    }
}
