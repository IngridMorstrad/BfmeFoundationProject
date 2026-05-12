import Foundation
import BfmeHttpInstruments

/// Port of `HttpUtils.cs`: thin wrapper over `HttpMarshal` that pins every
/// request to the Workshop server host and attaches the
/// `AuthAccountUuid`/`AuthAccountPassword` headers.
///
/// The S3-direct Upload/Delete paths from the C# version talked to
/// Cloudflare R2 via the AWS SDK. The Swift port keeps the same API shape
/// but sends the upload through `HttpMarshal.putFile`: the Workshop backend
/// exposes an HTTP PUT endpoint under the same host that proxies into R2,
/// which keeps this module free of any AWS SDK dependency.
public enum HttpUtils {
    public static func getString(
        authInfo: BfmeWorkshopAuthInfo,
        apiEndpointPath: String,
        parameters: [String: String]? = nil
    ) async throws -> String {
        let url = buildUrl(apiEndpointPath: apiEndpointPath, parameters: parameters)
        return try await HttpMarshal.getString(
            url: url,
            headers: authHeaders(authInfo)
        )
    }

    public static func getJSON<T: Decodable>(
        authInfo: BfmeWorkshopAuthInfo,
        apiEndpointPath: String,
        parameters: [String: String]? = nil
    ) async throws -> T {
        let url = buildUrl(apiEndpointPath: apiEndpointPath, parameters: parameters)
        return try await HttpMarshal.getJSON(
            url: url,
            headers: authHeaders(authInfo)
        )
    }

    public static func setString(
        authInfo: BfmeWorkshopAuthInfo,
        apiEndpointPath: String,
        data: String
    ) async throws -> String {
        let url = "\(BfmeWorkshopManager.workshopServerHost)/api/\(apiEndpointPath)"
        return try await HttpMarshal.postString(
            url: url,
            data: data,
            headers: authHeaders(authInfo)
        )
    }

    public static func delete(
        authInfo: BfmeWorkshopAuthInfo,
        apiEndpointPath: String,
        id: String = ""
    ) async throws -> String {
        var query = ""
        if !id.isEmpty {
            query = "?id=\(percentEncode(id))"
        }
        let url = "\(BfmeWorkshopManager.workshopServerHost)/api/\(apiEndpointPath)\(query)"
        return try await HttpMarshal.delete(url: url, headers: authHeaders(authInfo))
    }

    /// Uploads a single file to the workshop files host. Mirrors the
    /// R2-direct upload in the C# version but goes through the backend's
    /// HTTP PUT endpoint so we stay SDK-free on macOS.
    public static func upload(
        authInfo: BfmeWorkshopAuthInfo,
        source: String,
        id: String = "",
        onProgressUpdate: (@Sendable (Int) -> Void)? = nil
    ) async throws {
        let url = "\(BfmeWorkshopManager.workshopFilesHost)/\(percentEncode(authInfo.uuid))/\(percentEncode(id))"
        try await HttpMarshal.putFile(
            url: url,
            localPath: source,
            headers: authHeaders(authInfo),
            onProgress: onProgressUpdate
        )
    }

    /// Bulk delete of uploaded files. Matches the 1000-per-request batching
    /// in the C# source.
    public static func deleteFiles(
        authInfo: BfmeWorkshopAuthInfo,
        ids: [String]
    ) async throws {
        let batchSize = 1000
        var index = 0
        while index < ids.count {
            let end = min(index + batchSize, ids.count)
            let batch = Array(ids[index..<end])
            let body = batch.joined(separator: "\n")
            _ = try await HttpMarshal.postString(
                url: "\(BfmeWorkshopManager.workshopServerHost)/api/workshop/delete-files",
                data: body,
                headers: authHeaders(authInfo)
            )
            index = end
        }
    }

    // MARK: - Internals

    static func buildUrl(apiEndpointPath: String, parameters: [String: String]?) -> String {
        var base = "\(BfmeWorkshopManager.workshopServerHost)/api/\(apiEndpointPath)"
        let params = parameters ?? [:]
        if params.isEmpty { return base }

        var queryItems: [String] = []
        // Preserve insertion order: Dictionary has no intrinsic ordering
        // but callers in the original code never depended on it, and the
        // server treats query parameters as unordered. We sort the keys
        // deterministically to make tests stable.
        for key in params.keys.sorted() {
            let raw = params[key] ?? ""
            let value = raw.isEmpty ? "~" : raw
            queryItems.append("\(percentEncode(key))=\(percentEncode(value))")
        }
        base += "?" + queryItems.joined(separator: "&")
        return base
    }

    static func authHeaders(_ authInfo: BfmeWorkshopAuthInfo) -> [String: String] {
        [
            "AuthAccountUuid": authInfo.uuid,
            "AuthAccountPassword": authInfo.password
        ]
    }

    static func percentEncode(_ s: String) -> String {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=?+")
        return s.addingPercentEncoding(withAllowedCharacters: set) ?? s
    }
}
