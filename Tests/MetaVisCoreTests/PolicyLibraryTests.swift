import XCTest
import MetaVisCore

final class PolicyLibraryTests: XCTestCase {

    func testPolicyLibrarySaveLoadRoundTrip() throws {
        let qc = DeterministicQCPolicy(
            video: VideoContainerPolicy(
                minDurationSeconds: 1.9,
                maxDurationSeconds: 2.1,
                expectedWidth: 1920,
                expectedHeight: 1080,
                expectedNominalFrameRate: 24,
                minVideoSampleCount: 2
            ),
            requireAudioTrack: true,
            requireAudioNotSilent: true
        )

        let bundle = QualityPolicyBundle(
            export: .none,
            qc: qc,
            ai: nil,
            aiUsage: .localOnlyDefault,
            privacy: PrivacyPolicy(allowRawMediaUpload: false, allowDeliverablesUpload: false)
        )

        var library = PolicyLibrary()
        library.upsertPreset(named: "Cinema Master", bundle: bundle)

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("metavis_policy_library_tests")
            .appendingPathComponent("policies.json")

        try library.save(to: tmp)
        let loaded = try PolicyLibrary.load(from: tmp)

        XCTAssertEqual(loaded, library)
        XCTAssertEqual(loaded.listPresetNames(), ["Cinema Master"])
        XCTAssertEqual(loaded.preset(named: "Cinema Master"), bundle)
    }
}
