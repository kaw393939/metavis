import XCTest
import AVFoundation
import MetaVisCore
import MetaVisSession
import MetaVisExport
import MetaVisSimulation
import MetaVisQC

final class PolicyBundleTests: XCTestCase {

    func testBundleIncludesExportGovernance() async throws {
        let entitlements = EntitlementManager(initialPlan: .pro)
        let license = ProjectLicense(maxExportResolution: 4320, requiresWatermark: true)

        var timeline = GodTestBuilder.build()
        timeline.duration = Time(seconds: 1.0)

        let initial = ProjectState(
            timeline: timeline,
            config: ProjectConfig(name: "Policy Test", license: license),
            visualContext: nil
        )

        let session = ProjectSession(initialState: initial, entitlements: entitlements)
        let quality = QualityProfile(name: "Master 4K", fidelity: .master, resolutionHeight: 2160, colorDepth: 10)

        let bundle = await session.buildPolicyBundle(quality: quality, frameRate: 24, audioPolicy: .auto)

        XCTAssertEqual(bundle.export.userPlan, .pro)
        XCTAssertEqual(bundle.export.projectLicense?.requiresWatermark, true)
        XCTAssertNotNil(bundle.export.watermarkSpec)
    }

    func testPolicyBundleDrivesQC() async throws {
        DotEnvLoader.loadIfPresent()

        let entitlements = EntitlementManager(initialPlan: .pro)
        let license = ProjectLicense(maxExportResolution: 4320, requiresWatermark: true)

        var timeline = GodTestBuilder.build()
        timeline.duration = Time(seconds: 2.0)

        let initial = ProjectState(
            timeline: timeline,
            config: ProjectConfig(name: "Policy E2E", license: license),
            visualContext: nil
        )

        let session = ProjectSession(initialState: initial, entitlements: entitlements)

        let engine = try MetalSimulationEngine()
        try await engine.configure()
        let exporter = VideoExporter(engine: engine)

        let outputURL = Self.makeOutputURL(name: "policy_bundle_e2e")
        let quality = QualityProfile(name: "Master 4K", fidelity: .master, resolutionHeight: 2160, colorDepth: 10)

        try await session.exportMovie(
            using: exporter,
            to: outputURL,
            quality: quality,
            frameRate: 24,
            codec: .hevc,
            audioPolicy: .auto
        )

        let bundle = await session.buildPolicyBundle(quality: quality, frameRate: 24, audioPolicy: .auto)
        _ = try await VideoQC.validateMovie(at: outputURL, policy: bundle.qc)
    }

    private static func makeOutputURL(name: String) -> URL {
        let dir = URL(fileURLWithPath: "/tmp/metavis_session_tests")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(name).mov")
        try? FileManager.default.removeItem(at: url)
        return url
    }
}
