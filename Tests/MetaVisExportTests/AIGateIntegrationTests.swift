import XCTest
import MetaVisQC

final class AIGateIntegrationTests: XCTestCase {

    func testGeminiGateOptional() async throws {
        let hasKey = getenv("GEMINI_API_KEY") != nil || getenv("API__GOOGLE_API_KEY") != nil || getenv("GOOGLE_API_KEY") != nil
        if hasKey {
            throw XCTSkip("GEMINI_API_KEY present; skipping optional gate test")
        }

        let verdict = try await GeminiQC.acceptMulticlipExport(
            movieURL: URL(fileURLWithPath: "/tmp/does_not_matter.mov"),
            keyFrames: [.init(timeSeconds: 0.0, label: "start")],
            expectedNarrative: "N/A",
            requireKey: false
        )

        XCTAssertTrue(verdict.accepted)
        XCTAssertTrue(verdict.rawText.contains("SKIPPED"))
    }
}
