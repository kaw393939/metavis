import XCTest
@testable import MetaVisLab

final class TranscriptGenerateEnvGatingTests: XCTestCase {
    func test_transcript_generate_missingEnv_throwsClearError() async {
        unsetenv("WHISPERCPP_BIN")
        unsetenv("WHISPERCPP_MODEL")

        do {
            try await TranscriptCommand.run(args: [
                "generate",
                "--input", "Tests/Assets/people_talking/A_man_and_woman_talking.mp4",
                "--out", "test_outputs/_transcript_test"
            ])
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(
                String(describing: error).contains("WHISPERCPP_BIN") || String(describing: error).contains("WHISPERCPP_MODEL"),
                "Error should mention missing env vars. Got: \(error)"
            )
        }
    }

    func test_transcript_generate_nonexistentWhisperBin_throwsBeforeRunning() async {
        setenv("WHISPERCPP_BIN", "/no/such/whisper-cli", 1)
        setenv("WHISPERCPP_MODEL", "/no/such/ggml-model.bin", 1)

        do {
            try await TranscriptCommand.run(args: [
                "generate",
                "--input", "Tests/Assets/people_talking/A_man_and_woman_talking.mp4",
                "--out", "test_outputs/_transcript_test"
            ])
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(
                String(describing: error).lowercased().contains("does not exist"),
                "Error should mention missing WHISPERCPP_BIN path. Got: \(error)"
            )
        }
    }
}
