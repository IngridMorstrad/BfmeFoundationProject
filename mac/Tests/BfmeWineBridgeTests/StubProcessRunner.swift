import Foundation
@testable import BfmeWineBridge

/// Records every invocation and replays canned responses, so the bridge's
/// argument vectors and the `.reg` documents it writes can be asserted without
/// a Wine install.
final class StubProcessRunner: ProcessRunning, @unchecked Sendable {
    struct Invocation: Equatable {
        let executable: String
        let arguments: [String]
        let environment: [String: String]
    }

    private let lock = NSLock()
    private var _invocations: [Invocation] = []
    private var _capturedRegFiles: [String] = []

    /// Keyed by the first argument (the wine tool name), or "*" as a fallback.
    var responses: [String: ProcessResult] = [:]
    var defaultResult = ProcessResult(exitCode: 0, standardOutput: "", standardError: "")

    /// When set, a `regedit /E <path> <key>` call writes this document to
    /// `<path>`, standing in for a real prefix export. Left nil, no file is
    /// written, which is how regedit behaves for a key that does not exist.
    var exportDocument: RegistryDocument?

    var invocations: [Invocation] {
        lock.lock(); defer { lock.unlock() }
        return _invocations
    }

    /// Contents of any `.reg` file passed to regedit, captured before the
    /// bridge deletes it.
    var capturedRegFiles: [String] {
        lock.lock(); defer { lock.unlock() }
        return _capturedRegFiles
    }

    func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        currentDirectory: String?
    ) throws -> ProcessResult {
        lock.lock()
        _invocations.append(Invocation(executable: executable, arguments: arguments, environment: environment))

        if arguments.first == "regedit", arguments.count >= 2 {
            if arguments[1] == "/S", let path = arguments.last,
               let data = FileManager.default.contents(atPath: path) {
                // Import: capture the document before the bridge deletes it.
                let body = data.count >= 2 && data[data.startIndex] == 0xFF && data[data.startIndex + 1] == 0xFE
                    ? String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
                    : String(data: data, encoding: .utf8)
                if let body { _capturedRegFiles.append(body) }
            } else if arguments[1] == "/E", arguments.count >= 3, let document = exportDocument {
                // Export: emit the canned document at the requested path.
                try? document.serializedData().write(to: URL(fileURLWithPath: arguments[2]))
            }
        }
        lock.unlock()

        if let tool = arguments.first, let canned = responses[tool] { return canned }
        if let canned = responses["*"] { return canned }
        return defaultResult
    }
}

private extension FileManager {
    func contents(atPath path: String) -> Data? {
        FileManager.default.contents(atPath: path, options: [])
    }

    func contents(atPath path: String, options: Data.ReadingOptions) -> Data? {
        try? Data(contentsOf: URL(fileURLWithPath: path), options: options)
    }
}
