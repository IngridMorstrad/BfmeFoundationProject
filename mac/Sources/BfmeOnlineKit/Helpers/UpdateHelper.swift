import Foundation
import BfmeHttpInstruments

/// Port of `UpdateHelper.cs`. Pure-HTTP helper that checks whether the
/// arena backend is serving a newer build than the one we have on disk
/// and (when it is) downloads the replacement.
///
/// This is the portable half of the OnlineKit helpers (review bullet
/// #13): everything here is `HttpMarshal` + file IO so it ports cleanly
/// to macOS with no Win32 dependency. The Windows version computed an
/// MD5 fingerprint of the local exe to compare against the backend's
/// `versionHash`; we mirror that with `Md5Hash`.
public enum UpdateHelper {
    /// Checks whether the server's `versionHash` differs from the local
    /// build's MD5 fingerprint. Returns `true` when the exe is missing
    /// (the C# original returns "not_installed" as the local hash which
    /// is guaranteed to differ from any real backend hash).
    public static func isUpdateAvailable(branch: String) async throws -> Bool {
        let latest = try await HttpMarshal.getString(url: ArenaDataHelper.versionHashURL(branch: branch), headers: [:])
        let current = currentVersionHash()
        return latest != current
    }

    /// Downloads the latest arena build into
    /// `ArenaDataHelper.globalInstallPath/BfmeFoundationProject_OnlineArena.exe`,
    /// replacing any existing file. `onProgress` is called with the
    /// integer percentage as the download advances.
    public static func downloadLatest(
        branch: String,
        onProgress: (@Sendable (Int) -> Void)? = nil
    ) async throws {
        ArenaDataHelper.ensureDirectories()
        let destination = ArenaDataHelper.arenaExecutablePath
        if FileManager.default.fileExists(atPath: destination) {
            try FileManager.default.removeItem(atPath: destination)
        }
        try await HttpMarshal.getFile(
            url: ArenaDataHelper.binaryURL(branch: branch),
            localPath: destination,
            headers: [:],
            onProgress: onProgress
        )
    }

    /// Returns the MD5 fingerprint of the arena exe currently on disk as a
    /// hex string, or "not_installed" when nothing is installed. Kept
    /// internal-but-visible for unit tests.
    public static func currentVersionHash() -> String {
        let path = ArenaDataHelper.arenaExecutablePath
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return "not_installed"
        }
        return Md5Hash.hex(of: data)
    }
}

/// Minimal streaming-capable MD5 implementation. Used only as a fast-file
/// fingerprint for the arena update check; not security-critical. Kept
/// alongside `UpdateHelper` so the module stays self-contained (no
/// dependency on BfmeWorkshopKit's SHA/MD5 utilities).
enum Md5Hash {
    static func hex(of data: Data) -> String {
        var hasher = MD5State()
        hasher.update(data)
        let bytes = hasher.finalize()
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    struct MD5State {
        private var state: (UInt32, UInt32, UInt32, UInt32) = (
            0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476
        )
        private var buffer = Data()
        private var length: UInt64 = 0

        mutating func update(_ data: Data) {
            length = length &+ UInt64(data.count) &* 8
            buffer.append(data)
            while buffer.count >= 64 {
                let chunk = buffer.prefix(64)
                process(chunk)
                buffer.removeFirst(64)
            }
        }

        mutating func finalize() -> [UInt8] {
            let totalBits = length
            buffer.append(0x80)
            while buffer.count % 64 != 56 { buffer.append(0) }
            for i in 0..<8 {
                buffer.append(UInt8((totalBits >> (8 * i)) & 0xFF))
            }
            var cursor = 0
            while cursor < buffer.count {
                process(buffer.subdata(in: cursor..<cursor + 64))
                cursor += 64
            }
            var out = [UInt8]()
            for piece in [state.0, state.1, state.2, state.3] {
                for i in 0..<4 {
                    out.append(UInt8((piece >> (8 * i)) & 0xFF))
                }
            }
            return out
        }

        private mutating func process(_ chunk: Data) {
            var m = [UInt32](repeating: 0, count: 16)
            chunk.withUnsafeBytes { raw in
                for i in 0..<16 {
                    let base = i * 4
                    m[i] = UInt32(raw[base])
                        | (UInt32(raw[base + 1]) << 8)
                        | (UInt32(raw[base + 2]) << 16)
                        | (UInt32(raw[base + 3]) << 24)
                }
            }
            var a = state.0
            var b = state.1
            var c = state.2
            var d = state.3
            for i in 0..<64 {
                var f: UInt32
                var g: Int
                switch i {
                case 0..<16:
                    f = (b & c) | ((~b) & d); g = i
                case 16..<32:
                    f = (d & b) | ((~d) & c); g = (5 * i + 1) % 16
                case 32..<48:
                    f = b ^ c ^ d; g = (3 * i + 5) % 16
                default:
                    f = c ^ (b | (~d)); g = (7 * i) % 16
                }
                let temp = d
                d = c
                c = b
                b = b &+ Self.leftRotate(a &+ f &+ Self.kTable[i] &+ m[g], by: Self.sTable[i])
                a = temp
            }
            state.0 = state.0 &+ a
            state.1 = state.1 &+ b
            state.2 = state.2 &+ c
            state.3 = state.3 &+ d
        }

        private static func leftRotate(_ x: UInt32, by n: UInt32) -> UInt32 {
            (x << n) | (x >> (32 - n))
        }

        private static let sTable: [UInt32] = [
            7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22,
            5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20,
            4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23,
            6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21
        ]

        private static let kTable: [UInt32] = [
            0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
            0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
            0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
            0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
            0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
            0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
            0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
            0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
            0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
            0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
            0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
            0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
            0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
            0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
            0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
            0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391
        ]
    }
}
