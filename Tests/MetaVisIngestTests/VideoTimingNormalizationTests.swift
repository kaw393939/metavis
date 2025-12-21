import XCTest
@testable import MetaVisIngest

final class VideoTimingNormalizationTests: XCTestCase {

    func test_decide_prefersNominalFPS_andPassthroughWhenNotVFR() {
        let profile = VideoTimingProfile(
            nominalFPS: 29.97,
            estimatedFPS: 30.0,
            isVFRLikely: false,
            deltas: nil
        )

        let decision = VideoTimingNormalization.decide(profile: profile, fallbackFPS: 24.0)
        XCTAssertEqual(decision.mode, .passthrough)
        XCTAssertEqual(decision.targetFPS, 29.97, accuracy: 0.001)
        XCTAssertEqual(decision.frameStepSeconds, 1.0 / 29.97, accuracy: 1e-6)
    }

    func test_decide_snapsEstimatedFPS_toCommonTimebase() {
        let profile = VideoTimingProfile(
            nominalFPS: nil,
            estimatedFPS: 23.98,
            isVFRLikely: false,
            deltas: nil
        )

        let decision = VideoTimingNormalization.decide(profile: profile, fallbackFPS: 24.0)
        XCTAssertEqual(decision.targetFPS, 23.976, accuracy: 0.001)
    }

    func test_decide_vfrLikely_requestsNormalization() {
        let profile = VideoTimingProfile(
            nominalFPS: 30.0,
            estimatedFPS: 29.4,
            isVFRLikely: true,
            deltas: nil
        )

        let decision = VideoTimingNormalization.decide(profile: profile, fallbackFPS: 24.0)
        XCTAssertEqual(decision.mode, .normalizeToCFR)
        XCTAssertEqual(decision.targetFPS, 30.0, accuracy: 0.001)
    }

    func test_decide_usesFallbackFPS_whenNoNominalOrEstimatedFPS() {
        let profile = VideoTimingProfile(
            nominalFPS: nil,
            estimatedFPS: nil,
            isVFRLikely: true,
            deltas: nil
        )

        let decision = VideoTimingNormalization.decide(profile: profile, fallbackFPS: 60.0)
        XCTAssertEqual(decision.mode, .normalizeToCFR)
        XCTAssertEqual(decision.targetFPS, 60.0, accuracy: 0.001)
        XCTAssertEqual(decision.frameStepSeconds, 1.0 / 60.0, accuracy: 1e-6)
    }
}
