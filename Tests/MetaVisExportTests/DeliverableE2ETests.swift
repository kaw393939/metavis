import XCTest
import AVFoundation
import MetaVisCore
import MetaVisSession
import MetaVisExport
import MetaVisSimulation
import MetaVisQC

final class DeliverableE2ETests: XCTestCase {

    func test_export_deliverable_bundle_contains_mov_and_manifest() async throws {
        DotEnvLoader.loadIfPresent()

        let recipe = StandardRecipes.SmokeTest2s()
        let session = ProjectSession(recipe: recipe, entitlements: EntitlementManager(initialPlan: .pro))

        let engine = try MetalSimulationEngine()
        try await engine.configure()
        let exporter = VideoExporter(engine: engine)

        let bundleURL = TestOutputs.baseDirectory.appendingPathComponent("deliverable_smoke_4K_10bit", isDirectory: true)
        try? FileManager.default.removeItem(at: bundleURL)

        let quality = QualityProfile(
            name: "Master 4K",
            fidelity: .master,
            resolutionHeight: 2160,
            colorDepth: 10
        )

        _ = try await session.exportDeliverable(
            using: exporter,
            to: bundleURL,
            deliverable: .youtubeMaster,
            quality: quality,
            frameRate: 24,
            codec: .hevc,
            audioPolicy: .required
        )

        let movURL = bundleURL.appendingPathComponent("video.mov")
        let manifestURL = bundleURL.appendingPathComponent("deliverable.json")

        XCTAssertTrue(FileManager.default.fileExists(atPath: movURL.path), "Missing video.mov")
        XCTAssertTrue(FileManager.default.fileExists(atPath: manifestURL.path), "Missing deliverable.json")

        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(DeliverableManifest.self, from: data)

        XCTAssertEqual(manifest.schemaVersion, 4)
        XCTAssertEqual(manifest.deliverable, .youtubeMaster)
        XCTAssertEqual(manifest.quality, quality)
        XCTAssertEqual(manifest.frameRate, 24)
        XCTAssertEqual(manifest.codec, AVVideoCodecType.hevc.rawValue)
        XCTAssertEqual(manifest.audioPolicy, .required)

        XCTAssertEqual(manifest.timeline.durationSeconds, 2.0, accuracy: 0.0001)
        XCTAssertGreaterThan(manifest.timeline.trackCount, 0)

        XCTAssertNotNil(manifest.qcMetadataReport)
        XCTAssertNotNil(manifest.qcContentReport)
        XCTAssertNotNil(manifest.qcSidecarReport)
    }

    func test_export_deliverable_writes_sidecars_and_manifest_lists_them() async throws {
        DotEnvLoader.loadIfPresent()

        let recipe = StandardRecipes.SmokeTest2s()
        let session = ProjectSession(recipe: recipe, entitlements: EntitlementManager(initialPlan: .pro))

        let engine = try MetalSimulationEngine()
        try await engine.configure()
        let exporter = VideoExporter(engine: engine)

        let bundleURL = TestOutputs.baseDirectory.appendingPathComponent("deliverable_sidecars", isDirectory: true)
        try? FileManager.default.removeItem(at: bundleURL)

        let quality = QualityProfile(
            name: "Master 4K",
            fidelity: .master,
            resolutionHeight: 2160,
            colorDepth: 10
        )

        _ = try await session.exportDeliverable(
            using: exporter,
            to: bundleURL,
            deliverable: .youtubeMaster,
            quality: quality,
            frameRate: 24,
            codec: .hevc,
            audioPolicy: .required,
            sidecars: [
                .captionsVTT(),
                .thumbnailJPEG(),
                .contactSheetJPEG()
            ]
        )

        let movURL = bundleURL.appendingPathComponent("video.mov")
        let manifestURL = bundleURL.appendingPathComponent("deliverable.json")
        let vttURL = bundleURL.appendingPathComponent("captions.vtt")
        let thumbURL = bundleURL.appendingPathComponent("thumbnail.jpg")
        let sheetURL = bundleURL.appendingPathComponent("contact_sheet.jpg")

        XCTAssertTrue(FileManager.default.fileExists(atPath: movURL.path), "Missing video.mov")
        XCTAssertTrue(FileManager.default.fileExists(atPath: manifestURL.path), "Missing deliverable.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: vttURL.path), "Missing captions.vtt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: thumbURL.path), "Missing thumbnail.jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sheetURL.path), "Missing contact_sheet.jpg")

        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(DeliverableManifest.self, from: data)

        XCTAssertEqual(Set(manifest.sidecars.map { $0.kind }), Set([.captionsVTT, .thumbnailJPEG, .contactSheetJPEG]))

        XCTAssertNotNil(manifest.qcSidecarReport)
        XCTAssertEqual(Set(manifest.qcSidecarReport?.requested.map { $0.kind } ?? []), Set([.captionsVTT, .thumbnailJPEG, .contactSheetJPEG]))
        XCTAssertNotNil(manifest.qcSidecarReport?.requestedWithRequirements)
    }

    func test_manifest_contains_qc_results() async throws {
        DotEnvLoader.loadIfPresent()

        let recipe = StandardRecipes.SmokeTest2s()
        let session = ProjectSession(recipe: recipe, entitlements: EntitlementManager(initialPlan: .pro))

        let engine = try MetalSimulationEngine()
        try await engine.configure()
        let exporter = VideoExporter(engine: engine)

        let bundleURL = TestOutputs.baseDirectory.appendingPathComponent("deliverable_qc_4K_10bit", isDirectory: true)
        try? FileManager.default.removeItem(at: bundleURL)

        let quality = QualityProfile(
            name: "Master 4K",
            fidelity: .master,
            resolutionHeight: 2160,
            colorDepth: 10
        )

        _ = try await session.exportDeliverable(
            using: exporter,
            to: bundleURL,
            deliverable: .youtubeMaster,
            quality: quality,
            frameRate: 24,
            codec: .hevc,
            audioPolicy: .required
        )

        let movURL = bundleURL.appendingPathComponent("video.mov")
        let manifestURL = bundleURL.appendingPathComponent("deliverable.json")

        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(DeliverableManifest.self, from: data)

        let report = try await VideoQC.validateMovie(at: movURL, policy: manifest.qcPolicy)

        XCTAssertEqual(manifest.qcReport.width, report.width)
        XCTAssertEqual(manifest.qcReport.height, report.height)
        XCTAssertEqual(manifest.qcReport.videoSampleCount, report.videoSampleCount)
        XCTAssertEqual(manifest.qcReport.durationSeconds, report.durationSeconds, accuracy: 0.5)

        XCTAssertNotNil(manifest.qcMetadataReport)
        XCTAssertTrue(manifest.qcMetadataReport?.hasVideoTrack ?? false)
        XCTAssertTrue(manifest.qcMetadataReport?.hasAudioTrack ?? false)

        XCTAssertNotNil(manifest.qcContentReport)
        XCTAssertEqual(manifest.qcContentReport?.adjacentDistances.count, 2)
    }

    func test_export_uses_gpu_pixelbuffer_path_by_default() async throws {
        DotEnvLoader.loadIfPresent()

        MetalSimulationDiagnostics.reset()

        let recipe = StandardRecipes.SmokeTest2s()
        let session = ProjectSession(recipe: recipe, entitlements: EntitlementManager(initialPlan: .pro))

        let engine = try MetalSimulationEngine()
        try await engine.configure()
        let exporter = VideoExporter(engine: engine)

        let bundleURL = TestOutputs.baseDirectory.appendingPathComponent("deliverable_gpu_path_4K_10bit", isDirectory: true)
        try? FileManager.default.removeItem(at: bundleURL)

        let quality = QualityProfile(
            name: "Master 4K",
            fidelity: .master,
            resolutionHeight: 2160,
            colorDepth: 10
        )

        _ = try await session.exportDeliverable(
            using: exporter,
            to: bundleURL,
            deliverable: .youtubeMaster,
            quality: quality,
            frameRate: 24,
            codec: .hevc,
            audioPolicy: .required
        )

        XCTAssertEqual(MetalSimulationDiagnostics.cpuReadbackCount, 0, "Expected no CPU texture readback (texture.getBytes) during export")
    }

    func test_export_batch_creates_sub_bundles_with_manifests() async throws {
        DotEnvLoader.loadIfPresent()

        let recipe = StandardRecipes.SmokeTest2s()
        let session = ProjectSession(recipe: recipe, entitlements: EntitlementManager(initialPlan: .pro))

        let engine = try MetalSimulationEngine()
        try await engine.configure()
        let exporter = VideoExporter(engine: engine)

        let baseURL = TestOutputs.baseDirectory.appendingPathComponent("deliverable_batch", isDirectory: true)
        try? FileManager.default.removeItem(at: baseURL)

        let quality = QualityProfile(
            name: "Review 720p",
            fidelity: .high,
            resolutionHeight: 720,
            colorDepth: 8
        )

        let deliverables: [ExportDeliverable] = [.youtubeMaster, .reviewProxy]
        let manifests = try await session.exportBatch(
            using: exporter,
            to: baseURL,
            deliverables: deliverables,
            quality: quality,
            frameRate: 24,
            codec: .hevc,
            audioPolicy: .required
        )

        XCTAssertEqual(Set(manifests.map { $0.deliverable.id }), Set(deliverables.map { $0.id }))

        for deliverable in deliverables {
            let bundleURL = baseURL.appendingPathComponent(deliverable.id, isDirectory: true)
            let movURL = bundleURL.appendingPathComponent("video.mov")
            let manifestURL = bundleURL.appendingPathComponent("deliverable.json")

            XCTAssertTrue(FileManager.default.fileExists(atPath: movURL.path), "Missing video.mov for \(deliverable.id)")
            XCTAssertTrue(FileManager.default.fileExists(atPath: manifestURL.path), "Missing deliverable.json for \(deliverable.id)")

            let data = try Data(contentsOf: manifestURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let manifest = try decoder.decode(DeliverableManifest.self, from: data)

            XCTAssertEqual(manifest.deliverable, deliverable)
            XCTAssertEqual(manifest.quality, quality)
        }
    }

    func test_export_deliverable_fails_when_color_stats_policy_enforced_and_violated() async throws {
        DotEnvLoader.loadIfPresent()

        let recipe = StandardRecipes.SmokeTest2s()
        let session = ProjectSession(recipe: recipe, entitlements: EntitlementManager(initialPlan: .pro))

        let engine = try MetalSimulationEngine()
        try await engine.configure()
        let exporter = VideoExporter(engine: engine)

        let bundleURL = TestOutputs.baseDirectory.appendingPathComponent("deliverable_qc_enforced_should_fail", isDirectory: true)
        try? FileManager.default.removeItem(at: bundleURL)

        let quality = QualityProfile(
            name: "Master 4K",
            fidelity: .master,
            resolutionHeight: 2160,
            colorDepth: 10
        )

        let durationSeconds = 2.0
        let fps = 24.0
        let expectedFrames = Int((durationSeconds * fps).rounded())
        let minSamples = max(1, Int(Double(expectedFrames) * 0.85))
        let video = VideoContainerPolicy(
            minDurationSeconds: durationSeconds - 1.0,
            maxDurationSeconds: durationSeconds + 1.0,
            expectedWidth: quality.resolutionHeight * 16 / 9,
            expectedHeight: quality.resolutionHeight,
            expectedNominalFrameRate: fps,
            minVideoSampleCount: minSamples
        )

        let impossibleColorPolicy = VideoContentPolicy.ColorStatsPolicy(
            enforce: true,
            minMeanLuma: 2.0,
            maxMeanLuma: 3.0,
            maxChannelDelta: 0.0,
            minLowLumaFraction: 0.0,
            minHighLumaFraction: 0.0,
            maxDimension: 64
        )

        let qcOverride = DeterministicQCPolicy(
            video: video,
            content: VideoContentPolicy(minAdjacentDistance: 0.0, enforceTemporalVarietyIfMultipleClips: false, colorStats: impossibleColorPolicy),
            requireAudioTrack: true,
            requireAudioNotSilent: true
        )

        do {
            _ = try await session.exportDeliverable(
                using: exporter,
                to: bundleURL,
                deliverable: .youtubeMaster,
                quality: quality,
                frameRate: 24,
                codec: .hevc,
                audioPolicy: .required,
                qcPolicyOverrides: qcOverride
            )
            XCTFail("Expected exportDeliverable to throw when enforced color stats policy is violated")
        } catch {
            // Expected. (The bundle should not exist because DeliverableWriter is atomic.)
            XCTAssertFalse(FileManager.default.fileExists(atPath: bundleURL.path))
        }
    }
}
