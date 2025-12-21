import XCTest
import MetaVisQC
import MetaVisCore
import MetaVisServices

final class GeminiPromptBuilderTests: XCTestCase {

    func test_buildRequest_encodes_inlineData_and_fileData() throws {
        let evidence = GeminiPromptBuilder.Evidence(
            inline: [
                .init(label: "img", mimeType: "image/jpeg", data: Data([0x01, 0x02, 0x03]))
            ],
            fileUris: [
                .init(label: "vid", mimeType: "video/mp4", fileUri: "gs://bucket/video.mp4")
            ]
        )

        let req = GeminiPromptBuilder.buildRequest(prompt: "hello", evidence: evidence)
        let data = try JSONEncoder().encode(req)
        let json = String(data: data, encoding: .utf8) ?? ""

        XCTAssertTrue(json.contains("\"inline_data\""))
        XCTAssertTrue(json.contains("\"file_data\""))
        XCTAssertTrue(json.contains("\"mime_type\""))
        XCTAssertTrue(json.contains("\"file_uri\""))
    }

    func test_buildPrompt_includes_policy_privacy_redaction_and_metrics() {
        let policy = AIUsagePolicy(mode: .textImagesAndVideo, mediaSource: .deliverablesOnly)
        let privacy = PrivacyPolicy(allowRawMediaUpload: false, allowDeliverablesUpload: true)

        let context = GeminiPromptBuilder.PromptContext(
            expectedNarrative: "Expected: duration=2s, fps=24, resolution=3840x2160",
            keyFrameLabels: ["p10", "p50", "p90"],
            policy: policy,
            privacy: privacy,
            modelHint: "gemini-2.5-flash",
            metrics: .init(durationSeconds: 2.0, nominalFPS: 24.0, width: 3840, height: 2160)
        )

        let prompt = GeminiPromptBuilder.buildPrompt(context)
        XCTAssertTrue(prompt.contains("MODEL_HINT: gemini-2.5-flash"))
        XCTAssertTrue(prompt.contains("AI_POLICY:"))
        XCTAssertTrue(prompt.contains("PRIVACY:"))
        XCTAssertTrue(prompt.contains("REDACTION:"))
        XCTAssertTrue(prompt.contains("METRICS:"))
        XCTAssertTrue(prompt.contains("resolution=3840x2160"))
    }

    func test_geminiQC_skips_when_policy_disallows_network_even_if_key_present() async throws {
        let old = getenv("GEMINI_API_KEY").map { String(cString: $0) }
        setenv("GEMINI_API_KEY", "dummy", 1)
        defer {
            if let old {
                setenv("GEMINI_API_KEY", old, 1)
            } else {
                unsetenv("GEMINI_API_KEY")
            }
        }

        let usage = GeminiQC.UsageContext(policy: .localOnlyDefault, privacy: PrivacyPolicy())
        let verdict = try await GeminiQC.acceptMulticlipExport(
            movieURL: URL(fileURLWithPath: "/tmp/does_not_matter.mov"),
            keyFrames: [.init(timeSeconds: 0.0, label: "start")],
            expectedNarrative: "N/A",
            requireKey: false,
            usage: usage
        )

        XCTAssertTrue(verdict.accepted)
        XCTAssertTrue(verdict.rawText.contains("SKIPPED"))
        XCTAssertTrue(verdict.rawText.contains("AIUsagePolicy"))
        XCTAssertNil(verdict.model)
    }

    func test_buildPrompt_redacts_file_paths_and_identifiers_when_enabled() {
        let policy = AIUsagePolicy(
            mode: .textOnly,
            mediaSource: .deliverablesOnly,
            redaction: .init(redactFilePaths: true, redactIdentifiers: true)
        )
        let privacy = PrivacyPolicy(allowRawMediaUpload: false, allowDeliverablesUpload: true)

        let narrative = "Export /Users/alice/SecretProject/video.mov for user bob@example.com id=123e4567-e89b-12d3-a456-426614174000"
        let context = GeminiPromptBuilder.PromptContext(
            expectedNarrative: narrative,
            keyFrameLabels: ["p50"],
            policy: policy,
            privacy: privacy,
            modelHint: "gemini-2.5-flash",
            metrics: nil
        )

        let prompt = GeminiPromptBuilder.buildPrompt(context, notes: ["See /Users/alice/SecretProject/notes.txt"]) 
        XCTAssertFalse(prompt.contains("/Users/alice/SecretProject"))
        XCTAssertTrue(prompt.contains("video.mov"))
        XCTAssertTrue(prompt.contains("<EMAIL>"))
        XCTAssertTrue(prompt.contains("<UUID>"))
        XCTAssertFalse(prompt.contains("bob@example.com"))
        XCTAssertFalse(prompt.contains("123e4567-e89b-12d3-a456-426614174000"))
        XCTAssertTrue(prompt.contains("notes.txt"))
    }

    func test_buildPrompt_does_not_redact_when_disabled() {
        let policy = AIUsagePolicy(
            mode: .textOnly,
            mediaSource: .deliverablesOnly,
            redaction: .init(redactFilePaths: false, redactIdentifiers: false)
        )
        let privacy = PrivacyPolicy(allowRawMediaUpload: false, allowDeliverablesUpload: true)

        let narrative = "Export /Users/alice/SecretProject/video.mov for user bob@example.com id=123e4567-e89b-12d3-a456-426614174000"
        let context = GeminiPromptBuilder.PromptContext(
            expectedNarrative: narrative,
            keyFrameLabels: [],
            policy: policy,
            privacy: privacy
        )

        let prompt = GeminiPromptBuilder.buildPrompt(context)
        XCTAssertTrue(prompt.contains("/Users/alice/SecretProject/video.mov"))
        XCTAssertTrue(prompt.contains("bob@example.com"))
        XCTAssertTrue(prompt.contains("123e4567-e89b-12d3-a456-426614174000"))
    }

    func test_geminiQC_verdict_isCodable_and_preserves_model() throws {
        let verdict = GeminiQC.Verdict(accepted: true, rawText: "OK", model: "gemini-2.5-flash")
        let data = try JSONEncoder().encode(verdict)
        let decoded = try JSONDecoder().decode(GeminiQC.Verdict.self, from: data)
        XCTAssertEqual(decoded, verdict)
    }
}
