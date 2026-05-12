import Foundation

/// Port of `BfmeWorkshopQueryManager.cs`. Paginated queries against the
/// workshop HTTP API. All calls go through `HttpUtils` so they share the
/// auth-header wiring and the base URL.
public enum BfmeWorkshopQueryManager {
    public static func query(
        keyword: String = "",
        game: Int = -1,
        type: Int = -1,
        sortMode: Int = 0,
        page: Int = 0
    ) async throws -> [BfmeWorkshopEntryPreview] {
        do {
            let result: [BfmeWorkshopEntryPreview] = try await HttpUtils.getJSON(
                authInfo: .unauthenticated,
                apiEndpointPath: "workshop/query",
                parameters: [
                    "keyword": keyword,
                    "game": String(game),
                    "type": String(type),
                    "sortMode": String(sortMode),
                    "page": String(page)
                ]
            )
            return result
        } catch {
            return []
        }
    }

    public static func query(ownerUuid: String) async throws -> [BfmeWorkshopEntryPreview] {
        let items: [BfmeWorkshopEntryPreview] = (try? await HttpUtils.getJSON(
            authInfo: .unauthenticated,
            apiEndpointPath: "workshop/query",
            parameters: ["ownerUuid": ownerUuid]
        )) ?? []
        return sortedWorkshopEntries(items)
    }

    public static func queryAll(authInfo: BfmeWorkshopAuthInfo) async throws -> [BfmeWorkshopEntryPreview] {
        let items: [BfmeWorkshopEntryPreview] = (try? await HttpUtils.getJSON(
            authInfo: authInfo,
            apiEndpointPath: "workshop/query",
            parameters: ["ownerUuid": "*"]
        )) ?? []
        return sortedWorkshopEntries(items)
    }

    public static func get(entryGuid: String) async throws -> BfmeWorkshopEntryPreview {
        try await HttpUtils.getJSON(
            authInfo: .unauthenticated,
            apiEndpointPath: "workshop",
            parameters: ["guid": entryGuid]
        )
    }

    /// Replicates the multi-key ordering the C# version produces:
    /// `exp-original-*` first, then `original-*`, then `official-*`, then
    /// by name.
    static func sortedWorkshopEntries(_ items: [BfmeWorkshopEntryPreview]) -> [BfmeWorkshopEntryPreview] {
        items.sorted { lhs, rhs in
            func rank(_ p: BfmeWorkshopEntryPreview) -> Int {
                if p.guid.hasPrefix("exp-original-") { return 0 }
                if p.guid.hasPrefix("original-") { return 1 }
                if p.guid.hasPrefix("official-") { return 2 }
                return 3
            }
            let l = rank(lhs)
            let r = rank(rhs)
            if l != r { return l < r }
            return lhs.name < rhs.name
        }
    }
}
