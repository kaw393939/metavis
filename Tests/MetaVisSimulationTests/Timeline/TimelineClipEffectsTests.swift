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
                if SnapshotHelper.shouldRecordGoldens {
                    let url = try helper.saveGolden(name: goldenName, buffer: floats, width: width, height: height)
                    print("Updated Golden: \(url.path)")
                    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
                    return
                } else {
                    XCTFail("Timeline blur output differs from golden. max=\(maxDelta) avg=\(avgDelta) (set RECORD_GOLDENS=1 to update)")
                }
            }
        } else {
            if SnapshotHelper.shouldRecordGoldens {
                let url = try helper.saveGolden(name: goldenName, buffer: floats, width: width, height: height)
                print("Generated Golden: \(url.path)")
                XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
                return
            } else {
                XCTFail("Missing golden \(goldenName).exr (re-run with RECORD_GOLDENS=1 to record)")
            }
        }
    }

    func test_timelineRender_twoClipCrossfade_matchesGoldenOrRecords() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal not available")
        }

        // Pick a time that yields a non-50/50 mix so swapped bindings are detectable.
        let t = Time(seconds: 0.60)
        let crossfade = Transition.crossfade(duration: Time(seconds: 0.5))

        let clipA = Clip(
            name: "A",
            asset: AssetReference(sourceFn: "ligm://video/zone_plate"),
            startTime: .zero,
            duration: Time(seconds: 1.0),
            transitionOut: crossfade
        )

        let clipB = Clip(
            name: "B",
            asset: AssetReference(sourceFn: "ligm://video/smpte"),
            startTime: Time(seconds: 0.5),
            duration: Time(seconds: 1.0),
            transitionIn: crossfade
        )

        let track = Track(name: "V1", kind: .video, clips: [clipA, clipB])
        let timeline = Timeline(tracks: [track], duration: Time(seconds: 1.5))

        let compiler = TimelineCompiler()
        let quality = QualityProfile(name: "TimelineTransition", fidelity: .draft, resolutionHeight: 256, colorDepth: 32)
        let request = try await compiler.compile(timeline: timeline, at: t, quality: quality)

        // Compiler should emit a transition compositor for 2 overlapping clips.
        XCTAssertNotNil(request.graph.nodes.first(where: { $0.shader == "compositor_crossfade" }))

        let engine = try MetalSimulationEngine()
        try await engine.configure()

        func renderFloats(_ timeline: Timeline) async throws -> [Float] {
            let req = try await compiler.compile(timeline: timeline, at: t, quality: quality)
            let res = try await engine.render(request: req)
            guard let output = res.imageBuffer else {
                XCTFail("No output")
                return []
            }

            let width = 256
            let height = 256
            let expectedCount = width * height * 4
            let floats: [Float] = output.withUnsafeBytes { ptr in
                let base = ptr.bindMemory(to: Float.self)
                return Array(base.prefix(expectedCount))
            }
            XCTAssertEqual(floats.count, expectedCount)
            return floats
        }

        // Render A-only and B-only references.
        let aOnly = Timeline(tracks: [Track(name: "V1", kind: .video, clips: [clipA])], duration: Time(seconds: 1.0))
        let bOnly = Timeline(tracks: [Track(name: "V1", kind: .video, clips: [clipB])], duration: Time(seconds: 1.5))

        let bufA = try await renderFloats(aOnly)
        let bufB = try await renderFloats(bOnly)
        let bufMix = try await renderFloats(timeline)

        func meanAbsDiff(_ x: [Float], _ y: [Float]) -> Double {
            guard x.count == y.count, !x.isEmpty else { return .infinity }
            var acc: Double = 0
            for i in 0..<x.count {
                acc += Double(abs(x[i] - y[i]))
            }
            return acc / Double(x.count)
        }

        let diffToA = meanAbsDiff(bufMix, bufA)
        let diffToB = meanAbsDiff(bufMix, bufB)

        // At t=0.60 with a 0.5s crossfade that begins at 0.5, mix ~= 0.2, so output should be closer to A.
        XCTAssertGreaterThan(diffToA, 0.0)
        XCTAssertGreaterThan(diffToB, 0.0)
        XCTAssertLessThan(diffToA, diffToB)
    }
}
