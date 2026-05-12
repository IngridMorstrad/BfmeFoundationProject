import Foundation

/// Minimal archive extractor. Shells out to the `unzip` binary that ships on
/// both macOS and every mainstream Linux distribution. The BFME launcher only
/// ever extracts the bundled `dx9_redist.zip`, so a process invocation here
/// keeps the dependency surface small.
enum ZipExtractor {
    static func extract(zipURL: URL, into destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-q", zipURL.path, "-d", destination.path]

        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()

        do {
            try process.run()
        } catch {
            throw DirectXRuntimeError.extractionFailed("failed to invoke unzip: \(error)")
        }
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let data = try? stderr.fileHandleForReading.readToEnd()
            let message = (data.flatMap { String(data: $0, encoding: .utf8) }) ?? "unzip exited \(process.terminationStatus)"
            throw DirectXRuntimeError.extractionFailed(message)
        }
    }
}
