import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import BfmeHttpInstruments

/// Progress payload emitted while a workshop package is being downloaded.
public struct WorkshopDownloadProgress: Sendable, Equatable {
    public let fileName: String
    public let percent: Int
}

/// Port of `BfmeWorkshopDownloadManager.cs`. The original is a thin facade:
/// it only exposes a single `Download(guid)` call that pulls the
/// `BfmeWorkshopEntry` JSON descriptor and hands the file list off to the
/// sync manager. This port keeps that shape and additionally offers a
/// `downloadFiles(_:)` helper that fetches the raw files listed on the
/// entry (and optionally extracts .zip payloads) to support workshop
/// scenarios that predate the full sync manager.
public enum BfmeWorkshopDownloadManager {
    public static func download(_ entryGuid: String) async throws -> BfmeWorkshopEntry {
        try await HttpUtils.getJSON(
            authInfo: .unauthenticated,
            apiEndpointPath: "workshop/download",
            parameters: ["guid": entryGuid]
        )
    }

    /// Downloads every file listed on the entry into `destination` and
    /// emits progress via the returned `AsyncStream`. If a file ends in
    /// `.zip`, it is extracted in-place using `/usr/bin/unzip` (which ships
    /// on macOS and every mainstream Linux install).
    public static func downloadFiles(
        _ entry: BfmeWorkshopEntry,
        destination: URL,
        session: URLSession? = nil
    ) -> AsyncThrowingStream<WorkshopDownloadProgress, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let fm = FileManager.default
                do {
                    try fm.createDirectory(at: destination, withIntermediateDirectories: true)
                    for file in entry.files {
                        let dest = destination.appendingPathComponent(file.name)
                        if let parent = Optional(dest.deletingLastPathComponent()) {
                            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
                        }
                        continuation.yield(WorkshopDownloadProgress(fileName: file.name, percent: 0))
                        if let session = session {
                            try await downloadSingleFile(
                                url: file.url,
                                destination: dest,
                                session: session,
                                onProgress: { pct in
                                    continuation.yield(WorkshopDownloadProgress(fileName: file.name, percent: pct))
                                }
                            )
                        } else {
                            try await HttpMarshal.getFile(
                                url: file.url,
                                localPath: dest.path,
                                headers: [:],
                                onProgress: { pct in
                                    continuation.yield(WorkshopDownloadProgress(fileName: file.name, percent: pct))
                                }
                            )
                        }
                        continuation.yield(WorkshopDownloadProgress(fileName: file.name, percent: 100))

                        // Auto-extract .zip payloads so callers end up with
                        // a ready-to-use directory layout.
                        if dest.pathExtension.lowercased() == "zip" {
                            try extractZip(dest, into: destination)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Fetches a single URL through a caller-supplied `URLSession` (so tests
    /// can inject a `URLProtocol`-stubbed session). Writes the response
    /// body to `destination` atomically.
    public static func downloadSingleFile(
        url: String,
        destination: URL,
        session: URLSession,
        onProgress: (@Sendable (Int) -> Void)? = nil
    ) async throws {
        guard let parsed = URL(string: url) else {
            throw NSError(
                domain: "BfmeWorkshopDownloadManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Malformed URL: \(url)"]
            )
        }
        let request = URLRequest(url: parsed)
        let data: Data = try await withCheckedThrowingContinuation { cont in
            let task = session.dataTask(with: request) { body, response, error in
                if let error = error { cont.resume(throwing: error); return }
                if let http = response as? HTTPURLResponse,
                   !(200..<300).contains(http.statusCode) {
                    cont.resume(throwing: NSError(
                        domain: "BfmeWorkshopDownloadManager",
                        code: http.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"]
                    ))
                    return
                }
                cont.resume(returning: body ?? Data())
            }
            task.resume()
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination, options: .atomic)
        onProgress?(100)
    }

    /// Extracts a zip archive into `into` using the `unzip` binary. Used
    /// by `downloadFiles` to produce a ready-to-use directory layout.
    static func extractZip(_ archive: URL, into destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-q", archive.path, "-d", destination.path]
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let data = (try? stderr.fileHandleForReading.readToEnd()) ?? Data()
            let message = String(data: data, encoding: .utf8) ?? "unzip exited \(process.terminationStatus)"
            throw NSError(
                domain: "BfmeWorkshopDownloadManager",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }
}
