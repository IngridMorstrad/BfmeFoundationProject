import Foundation

/// Result of running an external command.
public struct ProcessResult: Equatable, Sendable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String

    public init(exitCode: Int32, standardOutput: String, standardError: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public var succeeded: Bool { exitCode == 0 }

    /// stdout with trailing newlines removed, which is what every `wine`
    /// helper tool needs (`winepath` in particular appends one).
    public var trimmedOutput: String {
        standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Injection seam for everything in this module that shells out. Tests
/// substitute a stub so the `.reg` documents and argument vectors can be
/// asserted without a Wine install present.
public protocol ProcessRunning: Sendable {
    func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        currentDirectory: String?
    ) throws -> ProcessResult
}

public extension ProcessRunning {
    func run(executable: String, arguments: [String], environment: [String: String]) throws -> ProcessResult {
        try run(executable: executable, arguments: arguments, environment: environment, currentDirectory: nil)
    }
}

/// Runs commands with `Foundation.Process`, merging the supplied environment
/// over the parent process environment.
public struct SystemProcessRunner: ProcessRunning {
    public init() {}

    public func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        currentDirectory: String?
    ) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        var merged = ProcessInfo.processInfo.environment
        for (key, value) in environment {
            merged[key] = value
        }
        process.environment = merged

        if let currentDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()

        // Read both pipes before waiting: a child that fills one pipe's buffer
        // while we block on waitUntilExit would deadlock.
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return ProcessResult(
            exitCode: process.terminationStatus,
            standardOutput: String(decoding: outData),
            standardError: String(decoding: errData)
        )
    }
}

private extension String {
    /// Wine tools emit UTF-8, but a prefix built from a non-UTF-8 locale can
    /// produce stray bytes. Falling back keeps a decode failure from turning
    /// into a crash.
    init(decoding data: Data) {
        if let utf8 = String(data: data, encoding: .utf8) {
            self = utf8
        } else {
            self = String(decoding: data, as: UTF8.self)
        }
    }
}
