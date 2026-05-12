import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import BfmeWorkshopKit
import BfmeHttpInstruments
import BfmeKitCore

/// Exercises the real download/extract paths in `BfmeWorkshopDownloadManager`
/// against a URLProtocol-stubbed `URLSession`.
final class BfmeWorkshopDownloadManagerTests: XCTestCase {
    private var sandbox: URL!

    override func setUpWithError() throws {
        sandbox = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("bfme-dl-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        StubURLProtocol.reset()
    }

    override func tearDownWithError() throws {
        StubURLProtocol.reset()
        if let sandbox {
            try? FileManager.default.removeItem(at: sandbox)
        }
    }

    private func makeSession() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: cfg)
    }

    func testDownloadSingleFileWritesBodyToDisk() async throws {
        let body = Data("hello-world".utf8)
        StubURLProtocol.register(url: "https://stub.local/foo.bin", body: body)

        let dest = sandbox.appendingPathComponent("foo.bin")
        try await BfmeWorkshopDownloadManager.downloadSingleFile(
            url: "https://stub.local/foo.bin",
            destination: dest,
            session: makeSession()
        )

        let written = try Data(contentsOf: dest)
        XCTAssertEqual(written, body)
    }

    func testDownloadSingleFileThrowsOnHttpError() async {
        StubURLProtocol.register(url: "https://stub.local/missing.bin", body: Data(), statusCode: 404)
        let dest = sandbox.appendingPathComponent("missing.bin")
        do {
            try await BfmeWorkshopDownloadManager.downloadSingleFile(
                url: "https://stub.local/missing.bin",
                destination: dest,
                session: makeSession()
            )
            XCTFail("Expected HTTP 404 to throw")
        } catch {
            // success
        }
    }

    func testDownloadFilesExtractsZipContents() async throws {
        // Build a real zip file on disk using the system `zip` binary.
        let zipSource = sandbox.appendingPathComponent("zip-src", isDirectory: true)
        try FileManager.default.createDirectory(at: zipSource, withIntermediateDirectories: true)
        let payload = zipSource.appendingPathComponent("hello.txt")
        try Data("greetings".utf8).write(to: payload)
        let zipFile = sandbox.appendingPathComponent("package.zip")

        let zipper = Process()
        zipper.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zipper.currentDirectoryURL = zipSource
        zipper.arguments = ["-q", zipFile.path, "hello.txt"]
        try zipper.run()
        zipper.waitUntilExit()
        XCTAssertEqual(zipper.terminationStatus, 0)

        let zipBytes = try Data(contentsOf: zipFile)
        StubURLProtocol.register(url: "https://stub.local/package.zip", body: zipBytes)

        let entry = BfmeWorkshopEntry(
            guid: "test-guid",
            name: "Test Package",
            version: "1.0",
            files: [
                BfmeWorkshopFile(
                    name: "package.zip",
                    url: "https://stub.local/package.zip",
                    md5: "",
                    size: Int64(zipBytes.count)
                )
            ]
        )

        let destDir = sandbox.appendingPathComponent("extract", isDirectory: true)
        var progressSeen: [WorkshopDownloadProgress] = []

        for try await event in BfmeWorkshopDownloadManager.downloadFiles(
            entry,
            destination: destDir,
            session: makeSession()
        ) {
            progressSeen.append(event)
        }

        let extracted = destDir.appendingPathComponent("hello.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: extracted.path),
                      "expected extracted file at \(extracted.path); progress=\(progressSeen)")
        let content = try String(contentsOf: extracted, encoding: .utf8)
        XCTAssertEqual(content, "greetings")
        XCTAssertTrue(progressSeen.contains(where: { $0.percent == 100 }),
                      "expected a 100% progress event, got \(progressSeen)")
    }
}

// MARK: - URLProtocol stub

final class StubURLProtocol: URLProtocol {
    struct Response {
        var body: Data
        var statusCode: Int
        var headers: [String: String]
    }

    nonisolated(unsafe) private static var responses: [String: Response] = [:]
    private static let lock = NSLock()

    static func register(url: String, body: Data, statusCode: Int = 200, headers: [String: String] = [:]) {
        lock.lock(); defer { lock.unlock() }
        responses[url] = Response(body: body, statusCode: statusCode, headers: headers)
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        responses.removeAll()
    }

    static func lookup(_ url: String) -> Response? {
        lock.lock(); defer { lock.unlock() }
        return responses[url]
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url?.absoluteString else { return false }
        return lookup(url) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let urlString = request.url?.absoluteString,
              let response = Self.lookup(urlString),
              let requestURL = request.url
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let http = HTTPURLResponse(
            url: requestURL,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: response.headers
        )!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
