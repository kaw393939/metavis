import XCTest
import Metal
import MetaVisCore
import MetaVisTimeline
@testable import MetaVisSimulation

final class TimelineClipEffectsTests: XCTestCase {
    func test_timelineCompiler_appliesRetimeAsTimeMapping_forProceduralSources() async throws {
        let clip = Clip(
            name: "Test",
            asset: AssetReference(sourceFn: "ligm://video/zone_plate"),
            startTime: .zero,
            duration: Time(seconds: 1.0),
            effects: [
                FeatureApplication(id: "mv.retime", parameters: ["factor": .float(2.0)])
            ]
        )
        let track = Track(name: "V1", kind: .video, clips: [clip])
        let timeline = Timeline(tracks: [track], duration: Time(seconds: 1.0))

        let compiler = TimelineCompiler()
        let quality = QualityProfile(name: "Test", fidelity: .draft, resolutionHeight: 256, colorDepth: 32)

        let request = try await compiler.compile(timeline: timeline, at: Time(seconds: 0.25), quality: quality)

        let node = try XCTUnwrap(request.graph.nodes.first(where: { $0.shader == "fx_zone_plate" }))
        let timeParam = try XCTUnwrap(node.parameters["time"])
        XCTAssertEqual(timeParam, .float(0.5))
    }

    func test_timelineCompiler_insertsClipEffectsNodes() async throws {
        let clip = Clip(
            name: "Test",
            asset: AssetReference(sourceFn: "ligm://source_test_color"),
            startTime: .zero,
            duration: Time(seconds: 1.0),
            effects: [
                FeatureApplication(
                    id: StandardFeatures.blurGaussian.id,
                    parameters: ["radius": .float(8.0)]
                )
            ]
        )
        let track = Track(name: "V1", kind: .video, clips: [clip])
        let timeline = Timeline(tracks: [track], duration: Time(seconds: 1.0))

        let compiler = TimelineCompiler()
        let quality = QualityProfile(name: "Test", fidelity: .draft, resolutionHeight: 256, colorDepth: 32)
        let request = try await compiler.compile(timeline: timeline, at: Time(seconds: 0.0), quality: quality)

        XCTAssertNotNil(request.graph.nodes.first(where: { $0.shader == "fx_blur_h" }))
        XCTAssertNotNil(request.graph.nodes.first(where: { $0.shader == "fx_blur_v" }))
    }

    func test_timelineRender_clipBlur_matchesGoldenOrRecords() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal not available")
        }

        let clip = Clip(
            name: "Test",
            asset: AssetReference(sourceFn: "ligm://source_test_color"),
            startTime: .zero,
            duration: Time(seconds: 1.0),
            effects: [
                FeatureApplication(
                    id: StandardFeatures.blurGaussian.id,
                    parameters: ["radius": .float(8.0)]
                )
            ]
        )
        let track = Track(name: "V1", kind: .video, clips: [clip])
        let timeline = Timeline(tracks: [track], duration: Time(seconds: 1.0))

        let compiler = TimelineCompiler()
        let quality = QualityProfile(name: "TimelineBlur", fidelity: .draft, resolutionHeight: 256, colorDepth: 32)
        let request = try await compiler.compile(timeline: timeline, at: Time(seconds: 0.0), quality: quality)

        let engine = try MetalSimulationEngine()
        try await engine.configure()

        let result = try await engine.render(request: request)
        guard let output = result.imageBuffer else {
            XCTFail("No output")
            return
        }

        let width = 256
        let height = 256
        let expectedCount = width * height * 4
        let floats: [Float] = output.withUnsafeBytes { ptr in
            let base = ptr.bindMemory(to: Float.self)
            return Array(base.prefix(expectedCount))
        }
        XCTAssertEqual(floats.count, expectedCount)

        let helper = SnapshotHelper()
        let goldenName = "Golden_Timeline_ClipEffect_BlurGaussian"

        if let golden = try helper.loadGolden(name: goldenName) {
            let compare = ImageComparator.compare(bufferA: floats, bufferB: golden)
            switch compare {
            case .match:
                XCTAssertTrue(true)
            case .different(let maxDelta, let avgDelta):
                XCTFail("Timeline blur output differs from golden. max=\(maxDelta) avg=\(avgDelta)")
            }
        } else {
            if SnapshotHelper.shouldRecordGoldens {
                _ = try helper.saveGolden(name: goldenName, buffer: floats, width: width, height: height)
                throw XCTSkip("Golden recorded; re-run to verify")
            } else {
                XCTFail("Missing golden \(goldenName).exr (re-run with RECORD_GOLDENS=1 to record)")
            }
        }
    }
}
