import XCTest
import AVFoundation
import MetaVisCore
import MetaVisSession
import MetaVisExport
import MetaVisSimulation
import MetaVisQC

final class RecipeE2ETests: XCTestCase {

    func testSmokeRecipeSessionExportAndQC() async throws {
        DotEnvLoader.loadIfPresent()

        let recipe = StandardRecipes.SmokeTest2s()
        let entitlements = EntitlementManager(initialPlan: .pro)
        let session = ProjectSession(recipe: recipe, entitlements: entitlements)

        let state = await session.state
        XCTAssertEqual(state.config.name, recipe.name)
        XCTAssertEqual(state.timeline.duration.seconds, 2.0, accuracy: 0.0001)

        let engine = try MetalSimulationEngine()
        try await engine.configure()
        let exporter = VideoExporter(engine: engine)

        let outputURL = TestOutputs.url(for: "recipe_smoke_session_e2e", quality: "4K_10bit")
        let quality = QualityProfile(
            name: "Master 4K",
            fidelity: .master,
            resolutionHeight: 2160,
            colorDepth: 10
        )

        try await session.exportMovie(
            using: exporter,
            to: outputURL,
            quality: quality,
            frameRate: 24,
            codec: .hevc,
            audioPolicy: .required
        )

        _ = try await VideoQC.validateMovie(
            at: outputURL,
            expectations: .hevc4K24fps(durationSeconds: 2.0)
        )
        try await VideoQC.assertHasAudioTrack(at: outputURL)
        try await VideoQC.assertAudioNotSilent(at: outputURL)
    }
}
