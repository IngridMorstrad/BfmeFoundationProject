import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Foundation-based port of `FileUtils.cs`. The C# version uses Win32
/// `CreateHardLink` for its `Link` helper; here we fall back to POSIX
/// `link(2)` via FileManager which is portable across macOS and Linux.
public enum FileUtils {
    /// Max number of times a read/write helper retries when the OS reports
    /// a transient IO failure. Matches the 100-iteration fallback in
    /// `ConfigUtils.SaveSyncProgress` and the general lenient behavior of
    /// the C# helpers that swallow `IOException`.
    static let retryCount = 3

    /// Async MD5 hash of a file's contents as lowercase hex. Returns `-1`
    /// when the file is missing, mirroring the C# sentinel.
    public static func hash(path: String) async -> String {
        guard FileManager.default.fileExists(atPath: path) else { return "-1" }
        return await Task.detached {
            guard let handle = FileHandle(forReadingAtPath: path) else { return "-1" }
            defer { try? handle.close() }
            #if canImport(CryptoKit)
            var hasher = Insecure.MD5()
            while true {
                let chunk = try? handle.read(upToCount: 1024 * 1024)
                guard let chunk, !chunk.isEmpty else { break }
                hasher.update(data: chunk)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
            #else
            var hasher = MD5()
            while true {
                let chunk = try? handle.read(upToCount: 1024 * 1024)
                guard let chunk, !chunk.isEmpty else { break }
                hasher.update(chunk)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
            #endif
        }.value
    }

    /// MD5 hash of an in-memory `Data` buffer as lowercase hex.
    public static func md5Hex(_ data: Data) -> String {
        #if canImport(CryptoKit)
        return Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #else
        var hasher = MD5()
        hasher.update(data)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        #endif
    }

    /// File size in bytes, or `-1` when the file is missing.
    public static func size(path: String) -> Int64 {
        guard FileManager.default.fileExists(atPath: path) else { return -1 }
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? -1
    }

    /// Read a text file as UTF-8. Returns `def` on any error. Retries a few
    /// times to survive concurrent writes from the Windows launcher.
    public static func readText(path: String, default def: String = "") -> String {
        for _ in 0..<retryCount {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let text = String(data: data, encoding: .utf8) {
                return text
            }
        }
        return def
    }

    /// Write text atomically. Swallows IO errors so it matches the C#
    /// helper's "best-effort" semantics.
    @discardableResult
    public static func writeText(path: String, data: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        let parent = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        for _ in 0..<retryCount {
            do {
                try data.data(using: .utf8)?.write(to: url, options: .atomic)
                return true
            } catch {
                continue
            }
        }
        return false
    }

    public static func readJSON<T: Decodable>(path: String, default def: T) -> T {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return def }
        let decoder = JSONDecoder()
        return (try? decoder.decode(T.self, from: data)) ?? def
    }

    @discardableResult
    public static func writeJSON<T: Encodable>(path: String, value: T) -> Bool {
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return false }
        for _ in 0..<retryCount {
            do {
                try data.write(to: url, options: .atomic)
                return true
            } catch {
                continue
            }
        }
        return false
    }

    public static func contains(path: String, text: String) -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let str = String(data: data, encoding: .utf8) else { return false }
        return str.contains(text)
    }

    /// Create a hard link at `path` pointing at `target`. On macOS/Linux
    /// this uses POSIX `link(2)` via FileManager.
    @discardableResult
    public static func link(path: String, target: String) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: path) {
            try? fm.removeItem(atPath: path)
        }
        do {
            try fm.linkItem(atPath: target, toPath: path)
            return true
        } catch {
            return false
        }
    }

    /// Copy an entire directory tree from `source` to `destination`, merging
    /// on top of any existing files. Used by the workshop sync path when it
    /// stages extracted mod contents into the install directory.
    public static func copyDirectory(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: destination.path) {
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        }
        let items = try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil, options: [])
        for item in items {
            let dest = destination.appendingPathComponent(item.lastPathComponent)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: item.path, isDirectory: &isDir)
            if isDir.boolValue {
                try copyDirectory(from: item, to: dest)
            } else {
                if fm.fileExists(atPath: dest.path) {
                    try fm.removeItem(at: dest)
                }
                try fm.copyItem(at: item, to: dest)
            }
        }
    }
}
