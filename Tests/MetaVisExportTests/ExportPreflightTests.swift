import XCTest
import MetaVisCore
import MetaVisTimeline
@testable import MetaVisExport

final class ExportPreflightTests: XCTestCase {
    func test_preflight_passesForKnownCrossDomainFeatures() async throws {
        let videoClip = Clip(
            name: "V",
            asset: AssetReference(sourceFn: "ligm://source_test_color"),
            startTime: .zero,
            duration: Time(seconds: 1.0),
            effects: [FeatureApplication(id: "mv.colorGrade")]
        )
        let audioClip = Clip(
            name: "A",
            asset: AssetReference(sourceFn: "file:///tmp/fake.wav"),
            startTime: .zero,
            duration: Time(seconds: 1.0),
            effects: [FeatureApplication(id: "audio.dialogCleanwater.v1")]
        )

        let timeline = Timeline(
            tracks: [
                Track(name: "V1", kind: .video, clips: [videoClip]),
                Track(name: "A1", kind: .audio, clips: [audioClip])
            ],
            duration: Time(seconds: 1.0)
        )

        let trace = InMemoryTraceSink()
        try await ExportPreflight.validateTimelineFeatureIDs(timeline, trace: trace)

        let events = await trace.snapshot()
        XCTAssertTrue(events.contains(where: { $0.name == "export.preflight.begin" }))
        XCTAssertTrue(events.contains(where: { $0.name == "export.preflight.end" }))
        XCTAssertTrue(events.contains(where: { $0.name == "export.preflight.non_video_effect_on_video_track" }))
    }

    func test_preflight_failsForUnknownFeature() async {
        let clip = Clip(
            name: "V",
            asset: AssetReference(sourceFn: "ligm://source_test_color"),
            startTime: .zero,
            duration: Time(seconds: 1.0),
            effects: [FeatureApplication(id: "does.not.exist")]
        )
        let timeline = Timeline(tracks: [Track(name: "V1", kind: .video, clips: [clip])], duration: Time(seconds: 1.0))

        await XCTAssertThrowsErrorAsync {
            try await ExportPreflight.validateTimelineFeatureIDs(timeline)
        }
    }
}

private func XCTAssertThrowsErrorAsync(_ body: @escaping () async throws -> Void) async {
    do {
        try await body()
        XCTFail("Expected error to be thrown")
    } catch {
        // success
    }
}
