import XCTest
import AVFoundation
import MetaVisCore
import MetaVisSession
import MetaVisExport
import MetaVisSimulation
import MetaVisQC

final class QCExpansionE2ETests: XCTestCase {

    func test_deliverable_manifest_embeds_expanded_qc_reports() async throws {
        DotEnvLoader.loadIfPresent()

        let recipe = StandardRecipes.SmokeTest2s()
        let session = ProjectSession(recipe: recipe, entitlements: EntitlementManager(initialPlan: .pro))

        let engine = try MetalSimulationEngine()
        try await engine.configure()
        let exporter = VideoExporter(engine: engine)

        let bundleURL = TestOutputs.baseDirectory.appendingPathComponent("deliverable_qc_expansion", isDirectory: true)
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
                .captionsSRT(fileName: "missing_dir/captions.srt", required: false)
            ]
        )

        let manifestURL = bundleURL.appendingPathComponent("deliverable.json")
        let data = try Data(contentsOf: manifestURL)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(DeliverableManifest.self, from: data)

        XCTAssertEqual(manifest.schemaVersion, 4)

        // Metadata QC
        guard let meta = manifest.qcMetadataReport else {
            return XCTFail("Missing qcMetadataReport")
        }
        XCTAssertTrue(meta.hasVideoTrack)
        XCTAssertTrue(meta.hasAudioTrack)
        XCTAssertNotNil(meta.videoCodecFourCC)

        // Content QC
        guard let content = manifest.qcContentReport else {
            return XCTFail("Missing qcContentReport")
        }
        XCTAssertEqual(content.samples.count, 3)
        XCTAssertEqual(content.adjacentDistances.count, 2)
        XCTAssertNotNil(content.enforced)
        XCTAssertTrue(content.adjacentDistances.allSatisfy { $0.distance.isFinite && $0.distance >= 0 })

        // Histogram-derived luma metrics persisted per sample.
        XCTAssertTrue(content.samples.allSatisfy { $0.lumaStats != nil })
        XCTAssertTrue(content.samples.allSatisfy {
            guard let s = $0.lumaStats else { return false }
            return s.meanLuma.isFinite
                && s.meanLuma >= 0 && s.meanLuma <= 1
                && s.lowLumaFraction.isFinite
                && s.lowLumaFraction >= 0 && s.lowLumaFraction <= 1
                && s.highLumaFraction.isFinite
                && s.highLumaFraction >= 0 && s.highLumaFraction <= 1
                && (0...255).contains(s.peakLumaBin)
        })

        // Sidecar QC
        guard let sidecarQC = manifest.qcSidecarReport else {
            return XCTFail("Missing qcSidecarReport")
        }
        XCTAssertEqual(Set(sidecarQC.requested.map { $0.kind }), Set([.captionsVTT, .thumbnailJPEG, .captionsSRT]))
        XCTAssertEqual(Set(sidecarQC.written.map { $0.kind }), Set([.captionsVTT, .thumbnailJPEG]))
        XCTAssertTrue(sidecarQC.written.allSatisfy { $0.fileBytes > 0 })

        XCTAssertNotNil(sidecarQC.requestedWithRequirements)
        XCTAssertTrue(sidecarQC.optionalFailures?.contains(where: { $0.kind == .captionsSRT }) ?? false)
    }
}
