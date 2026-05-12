import XCTest
@testable import BfmeDirectXRuntime

final class DirectXRuntimeManagerTests: XCTestCase {
    func testSurveyHostDoesNotThrowAndReturnsDeterministicSummary() {
        // The sandbox has none of Whisky / CrossOver / GPTK installed so the
        // survey is expected to be empty. This still exercises every probe.
        let survey = DirectXRuntimeManager.surveyHost()
        XCTAssertFalse(survey.hasAnyRuntime)
        XCTAssertEqual(survey.summary, "No Wine-compatible runtime detected.")
    }

    func testResourceBundleExposesDx9RedistZip() {
        let url = DirectXRuntimeManager.resourceBundle.url(forResource: "dx9_redist", withExtension: "zip")
        XCTAssertNotNil(url, "dx9_redist.zip must be bundled as a module resource")
        if let url = url {
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
            XCTAssertGreaterThan(size, 1_000_000, "dx9_redist.zip should be the real resource, not a stub")
        }
    }

    func testEnsureRuntimesCreatesFlagAndExtractsIntoSandbox() async throws {
        let sandbox = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("bfme-dx-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        var logs: [String] = []
        let survey = try await DirectXRuntimeManager.ensureRuntimes(
            destination: sandbox,
            logger: { logs.append($0) }
        )
        XCTAssertFalse(survey.hasAnyRuntime)
        XCTAssertFalse(logs.isEmpty)

        let flagURL = sandbox
            .appendingPathComponent("Config")
            .appendingPathComponent("dx_version.flag")
        XCTAssertTrue(FileManager.default.fileExists(atPath: flagURL.path))

        let extractDir = sandbox
            .appendingPathComponent("DirectX")
            .appendingPathComponent("dx9_redist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: extractDir.path))

        let contents = try FileManager.default.contentsOfDirectory(atPath: extractDir.path)
        XCTAssertFalse(contents.isEmpty, "extraction should produce at least one file")
    }

    func testEnsureRuntimesIsIdempotent() async throws {
        let sandbox = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("bfme-dx-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        _ = try await DirectXRuntimeManager.ensureRuntimes(destination: sandbox)
        let flagURL = sandbox
            .appendingPathComponent("Config")
            .appendingPathComponent("dx_version.flag")
        let firstMtime = (try? FileManager.default.attributesOfItem(atPath: flagURL.path)[.modificationDate] as? Date)

        // Second invocation should skip extraction but still rewrite the flag.
        _ = try await DirectXRuntimeManager.ensureRuntimes(destination: sandbox)
        XCTAssertTrue(FileManager.default.fileExists(atPath: flagURL.path))
        XCTAssertNotNil(firstMtime)
    }
}
