import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum HttpMarshalError: Error, CustomStringConvertible {
    case requestFailed(method: String, url: String, underlying: Error?)
    case badStatus(method: String, url: String, statusCode: Int)
    case decodeFailed(reason: String)

    public var description: String {
        switch self {
        case .requestFailed(let method, let url, let underlying):
            if let e = underlying {
                return "\(method) failed! URL: \(url)\n\(e)"
            }
            return "\(method) failed! URL: \(url)"
        case .badStatus(let method, let url, let statusCode):
            return "\(method) failed! URL: \(url)\nStatus \(statusCode)"
        case .decodeFailed(let reason):
            return "Decode failed: \(reason)"
        }
    }
}

/// A Foundation URLSession port of the original C# `HttpMarshal`. The shape
/// (5-retry loop, 90s default timeout, 5h upload timeout, Chrome-like UA)
/// matches the C# source one-to-one.
public enum HttpMarshal {
    private static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"
    private static let maxRetries = 5
    private static let defaultTimeout: TimeInterval = 90
    private static let uploadTimeout: TimeInterval = 5 * 60 * 60

    /// Shared session re-used across calls to keep connections pooled, which
    /// mirrors the single static `SocketsHttpHandler` in the C# original.
    static let sharedSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = defaultTimeout
        config.timeoutIntervalForResource = defaultTimeout
        config.httpMaximumConnectionsPerHost = 10
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        return URLSession(configuration: config)
    }()

    private static let uploadSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = uploadTimeout
        config.timeoutIntervalForResource = uploadTimeout
        config.httpMaximumConnectionsPerHost = 10
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        return URLSession(configuration: config)
    }()

    // MARK: - Public API

    /// Performs an HTTP GET and returns the response body as a UTF-8 string.
    /// If the server returns `Content-Encoding: b64-gzip`, decodes the BFME
    /// custom envelope: Base64 -> 4-byte little-endian length header -> gzip
    /// payload -> UTF-8.
    public static func getString(url: String, headers: [String: String] = [:]) async throws -> String {
        var lastError: Error?
        for attempt in 1...maxRetries {
            do {
                return try await performGetString(url: url, headers: headers)
            } catch {
                lastError = error
                if attempt == maxRetries {
                    throw HttpMarshalError.requestFailed(method: "GET", url: url, underlying: error)
                }
            }
        }
        throw HttpMarshalError.requestFailed(method: "GET", url: url, underlying: lastError)
    }

    /// Downloads the body of an HTTP GET to `localPath`. `onProgress` is
    /// invoked with integer percentages (0-100) any time the value changes.
    public static func getFile(
        url: String,
        localPath: String,
        headers: [String: String] = [:],
        onProgress: (@Sendable (Int) -> Void)? = nil
    ) async throws {
        var lastError: Error?
        for attempt in 1...maxRetries {
            do {
                try await performGetFile(url: url, localPath: localPath, headers: headers, onProgress: onProgress)
                return
            } catch {
                lastError = error
                onProgress?(0)
                if attempt == maxRetries {
                    throw HttpMarshalError.requestFailed(method: "GET", url: url, underlying: error)
                }
            }
        }
        throw HttpMarshalError.requestFailed(method: "GET", url: url, underlying: lastError)
    }

    /// Performs an HTTP GET and decodes the body as JSON into `T`.
    public static func getJSON<T: Decodable>(url: String, headers: [String: String] = [:]) async throws -> T {
        let string = try await getString(url: url, headers: headers)
        guard let data = string.data(using: .utf8) else {
            throw HttpMarshalError.decodeFailed(reason: "Response body is not valid UTF-8")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Performs an HTTP POST with a UTF-8 text/plain body and returns the
    /// response as a string.
    public static func postString(url: String, data: String, headers: [String: String] = [:]) async throws -> String {
        var lastError: Error?
        for attempt in 1...maxRetries {
            do {
                return try await performPostString(url: url, data: data, headers: headers)
            } catch {
                lastError = error
                if attempt == maxRetries {
                    throw HttpMarshalError.requestFailed(method: "POST", url: url, underlying: error)
                }
            }
        }
        throw HttpMarshalError.requestFailed(method: "POST", url: url, underlying: lastError)
    }

    /// Uploads the file at `localPath` via HTTP PUT.
    public static func putFile(
        url: String,
        localPath: String,
        headers: [String: String] = [:],
        onProgress: (@Sendable (Int) -> Void)? = nil
    ) async throws {
        var lastError: Error?
        for attempt in 1...maxRetries {
            do {
                try await performPutFile(url: url, localPath: localPath, headers: headers, onProgress: onProgress)
                return
            } catch {
                lastError = error
                if attempt == maxRetries {
                    throw HttpMarshalError.requestFailed(method: "PUT", url: url, underlying: error)
                }
            }
        }
        throw HttpMarshalError.requestFailed(method: "PUT", url: url, underlying: lastError)
    }

    /// Performs an HTTP DELETE and returns the response body.
    public static func delete(url: String, headers: [String: String] = [:]) async throws -> String {
        var lastError: Error?
        for attempt in 1...maxRetries {
            do {
                return try await performDelete(url: url, headers: headers)
            } catch {
                lastError = error
                if attempt == maxRetries {
                    throw HttpMarshalError.requestFailed(method: "DELETE", url: url, underlying: error)
                }
            }
        }
        throw HttpMarshalError.requestFailed(method: "DELETE", url: url, underlying: lastError)
    }

    // MARK: - b64-gzip envelope

    /// Decodes the BFME `b64-gzip` envelope: Base64 string -> raw bytes whose
    /// first four bytes are a little-endian uncompressed length, followed by
    /// a gzip stream that decompresses to UTF-8.
    public static func decodeB64Gzip(_ responseString: String) throws -> String {
        guard let gzipBuffer = Data(base64Encoded: responseString, options: [.ignoreUnknownCharacters]) else {
            throw HttpMarshalError.decodeFailed(reason: "Input is not valid base64")
        }
        guard gzipBuffer.count > 4 else {
            throw HttpMarshalError.decodeFailed(reason: "Payload too short for length prefix")
        }

        // 4-byte little-endian length header, then the gzip stream.
        let expectedLength: Int = gzipBuffer.withUnsafeBytes { raw -> Int in
            let b0 = Int(raw[0])
            let b1 = Int(raw[1]) << 8
            let b2 = Int(raw[2]) << 16
            let b3 = Int(raw[3]) << 24
            return b0 | b1 | b2 | b3
        }
        let gzipStart = gzipBuffer.startIndex + 4
        let gzipPayload = gzipBuffer.subdata(in: gzipStart..<gzipBuffer.endIndex)
        let decompressed = try GzipDecoder.decompress(gzipPayload)
        // Truncate/pad to expected length when the server advertised one.
        let bytes: Data
        if expectedLength >= 0 && decompressed.count >= expectedLength {
            let end = decompressed.startIndex + expectedLength
            bytes = decompressed.subdata(in: decompressed.startIndex..<end)
        } else {
            bytes = decompressed
        }
        guard let text = String(data: bytes, encoding: .utf8) else {
            throw HttpMarshalError.decodeFailed(reason: "Decoded payload is not valid UTF-8")
        }
        return text
    }

    /// Encodes a UTF-8 string as the BFME `b64-gzip` envelope. Primarily a
    /// round-trip helper for tests.
    public static func encodeB64Gzip(_ plain: String) throws -> String {
        guard let utf8 = plain.data(using: .utf8) else {
            throw HttpMarshalError.decodeFailed(reason: "Input is not valid UTF-8")
        }
        let compressed = try GzipDecoder.compress(utf8)
        var out = Data()
        out.append(BinaryUtils_writeUInt32LE(UInt32(utf8.count)))
        out.append(compressed)
        return out.base64EncodedString()
    }

    // MARK: - Internals

    /// Writes a 32-bit little-endian integer without pulling the BfmeKitCore
    /// module into this target's build graph.
    private static func BinaryUtils_writeUInt32LE(_ value: UInt32) -> Data {
        var out = Data(count: 4)
        out[0] = UInt8(value & 0xFF)
        out[1] = UInt8((value >> 8) & 0xFF)
        out[2] = UInt8((value >> 16) & 0xFF)
        out[3] = UInt8((value >> 24) & 0xFF)
        return out
    }

    private static func makeRequest(url: String, method: String, headers: [String: String], timeout: TimeInterval) throws -> URLRequest {
        guard let parsed = URL(string: url) else {
            throw HttpMarshalError.decodeFailed(reason: "Malformed URL: \(url)")
        }
        var request = URLRequest(url: parsed)
        request.httpMethod = method
        request.timeoutInterval = timeout
        // The shared session already injects User-Agent, but headers on the
        // request win so we re-assert here to keep parity with the C# code.
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }
        return request
    }

    private static func validate(_ response: URLResponse, method: String, url: String) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else {
            throw HttpMarshalError.requestFailed(method: method, url: url, underlying: nil)
        }
        if !(200..<300).contains(http.statusCode) {
            throw HttpMarshalError.badStatus(method: method, url: url, statusCode: http.statusCode)
        }
        return http
    }

    private static func contentEncoding(_ response: HTTPURLResponse) -> String? {
        // HTTPURLResponse headers are case-insensitive in the Apple runtime
        // but not on swift-corelibs-foundation. Check both spellings.
        if let v = response.value(forHTTPHeaderField: "Content-Encoding") { return v }
        return (response.allHeaderFields["Content-Encoding"] as? String)
    }

    private static func performGetString(url: String, headers: [String: String]) async throws -> String {
        let request = try makeRequest(url: url, method: "GET", headers: headers, timeout: defaultTimeout)
        let (data, response) = try await dataTaskAsync(request: request, session: sharedSession)
        let http = try validate(response, method: "GET", url: url)
        guard var body = String(data: data, encoding: .utf8) else {
            throw HttpMarshalError.decodeFailed(reason: "Response is not valid UTF-8")
        }
        if !body.isEmpty, let enc = contentEncoding(http), enc.contains("b64-gzip") {
            body = try decodeB64Gzip(body)
        }
        return body
    }

    private static func performPostString(url: String, data: String, headers: [String: String]) async throws -> String {
        var request = try makeRequest(url: url, method: "POST", headers: headers, timeout: defaultTimeout)
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = data.data(using: .utf8)
        let (respData, response) = try await dataTaskAsync(request: request, session: sharedSession)
        _ = try validate(response, method: "POST", url: url)
        return String(data: respData, encoding: .utf8) ?? ""
    }

    private static func performDelete(url: String, headers: [String: String]) async throws -> String {
        let request = try makeRequest(url: url, method: "DELETE", headers: headers, timeout: defaultTimeout)
        let (respData, response) = try await dataTaskAsync(request: request, session: sharedSession)
        _ = try validate(response, method: "DELETE", url: url)
        return String(data: respData, encoding: .utf8) ?? ""
    }

    private static func performGetFile(
        url: String,
        localPath: String,
        headers: [String: String],
        onProgress: (@Sendable (Int) -> Void)?
    ) async throws {
        let request = try makeRequest(url: url, method: "GET", headers: headers, timeout: uploadTimeout)
        let (data, response) = try await dataTaskAsync(request: request, session: uploadSession, onProgress: onProgress)
        _ = try validate(response, method: "GET", url: url)
        let dest = URL(fileURLWithPath: localPath)
        try FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try data.write(to: dest, options: .atomic)
    }

    private static func performPutFile(
        url: String,
        localPath: String,
        headers: [String: String],
        onProgress: (@Sendable (Int) -> Void)?
    ) async throws {
        let request = try makeRequest(url: url, method: "PUT", headers: headers, timeout: uploadTimeout)
        let fileURL = URL(fileURLWithPath: localPath)
        let (_, response) = try await uploadTaskAsync(request: request, fileURL: fileURL, session: uploadSession, onProgress: onProgress)
        _ = try validate(response, method: "PUT", url: url)
    }

    // MARK: - URLSession adapters

    /// Wraps `URLSession.dataTask` in a cancellable async call. We avoid
    /// `URLSession.data(for:)` so that this module compiles against the
    /// swift-corelibs-foundation URLSession on Linux, which doesn't ship the
    /// async convenience methods in every release.
    private static func dataTaskAsync(
        request: URLRequest,
        session: URLSession,
        onProgress: (@Sendable (Int) -> Void)? = nil
    ) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
            let task = session.dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data = data, let response = response else {
                    continuation.resume(throwing: HttpMarshalError.requestFailed(
                        method: request.httpMethod ?? "?",
                        url: request.url?.absoluteString ?? "",
                        underlying: nil
                    ))
                    return
                }
                continuation.resume(returning: (data, response))
            }
            // Wire up progress callbacks when the caller provided them.
            if let onProgress = onProgress {
                let observer = ProgressObserver(handler: onProgress)
                observer.observe(task)
            }
            task.resume()
        }
    }

    private static func uploadTaskAsync(
        request: URLRequest,
        fileURL: URL,
        session: URLSession,
        onProgress: (@Sendable (Int) -> Void)? = nil
    ) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
            let task = session.uploadTask(with: request, fromFile: fileURL) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let response = response else {
                    continuation.resume(throwing: HttpMarshalError.requestFailed(
                        method: request.httpMethod ?? "?",
                        url: request.url?.absoluteString ?? "",
                        underlying: nil
                    ))
                    return
                }
                continuation.resume(returning: (data ?? Data(), response))
            }
            if let onProgress = onProgress {
                let observer = ProgressObserver(handler: onProgress)
                observer.observe(task)
            }
            task.resume()
        }
    }
}

/// Polls a URLSessionTask's `countOfBytesReceived`/`countOfBytesSent`
/// counters on a background queue and pipes integer percentages (0-100) to
/// the handler. This is portable across Darwin and swift-corelibs-foundation,
/// unlike `NSKeyValueChangeKey`-based KVO which is Darwin-only.
private final class ProgressObserver: @unchecked Sendable {
    private let handler: @Sendable (Int) -> Void
    private var task: URLSessionTask?
    private var lastReported: Int = -1
    private var retainedSelf: ProgressObserver?
    private var timer: DispatchSourceTimer?

    init(handler: @escaping @Sendable (Int) -> Void) {
        self.handler = handler
    }

    func observe(_ task: URLSessionTask) {
        self.task = task
        self.retainedSelf = self
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(200))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    private func tick() {
        guard let task = task else { return }
        let sendExpected = task.countOfBytesExpectedToSend
        let sendCurrent = task.countOfBytesSent
        let recvExpected = task.countOfBytesExpectedToReceive
        let recvCurrent = task.countOfBytesReceived

        let total: Int64
        let current: Int64
        if sendExpected > 0 && sendCurrent > 0 {
            total = sendExpected
            current = sendCurrent
        } else if recvExpected > 0 {
            total = recvExpected
            current = recvCurrent
        } else {
            if task.state == .completed { detach() }
            return
        }

        let pct = Int((Double(current) / Double(total)) * 100.0)
        if pct != lastReported {
            lastReported = pct
            handler(pct)
        }
        if task.state == .completed {
            detach()
        }
    }

    private func detach() {
        timer?.cancel()
        timer = nil
        task = nil
        retainedSelf = nil
    }

    deinit {
        detach()
    }
}
