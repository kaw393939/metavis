import XCTest
import Metal
import MetaVisCore
import MetaVisGraphics
@testable import MetaVisSimulation

final class ACESODTPerformanceComparisonTests: XCTestCase {

    private struct NodeTimingLine {
        var name: String
        var shader: String
        var gpuMs: Double?
    }

    private func parseNodeTimings(_ s: String) -> [NodeTimingLine] {
        // Format (from MetalSimulationEngine):
        //   Name[shader]=12.34ms | Other[shader]=n/a
        return s
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap { part in
                guard let lb = part.firstIndex(of: "["),
                      let rb = part.firstIndex(of: "]"),
                      let eq = part.firstIndex(of: "=") else {
                    return nil
                }
                let name = String(part[..<lb])
                let shader = String(part[part.index(after: lb)..<rb])
                let rhs = part[part.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                if rhs == "n/a" {
                    return NodeTimingLine(name: name, shader: shader, gpuMs: nil)
                }
                // e.g. "0.12ms"
                let msString = rhs.replacingOccurrences(of: "ms", with: "")
                let ms = Double(msString)
                return NodeTimingLine(name: name, shader: shader, gpuMs: ms)
            }
    }

    private func percentile(_ xs: [Double], _ p: Double) -> Double {
        precondition(!xs.isEmpty)
        let sorted = xs.sorted()
        let idx = Int(round((Double(sorted.count) - 1.0) * p))
        return sorted[max(0, min(sorted.count - 1, idx))]
    }

    func test_odt_perf_lut_vs_shader_opt_in() async throws {
        guard ProcessInfo.processInfo.environment["METAVIS_RUN_ODT_PERF"] == "1" else {
            throw XCTSkip("Set METAVIS_RUN_ODT_PERF=1 to run LUT vs shader ODT perf comparison")
        }
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal not available")
        }
        guard let sdrLUT = LUTResources.aces13SDRSRGBDisplayRRTODT33() else {
            throw XCTSkip("Missing ACES 1.3 SDR LUT resource")
        }
        guard let hdrLUT = LUTResources.aces13HDRRec2100PQ1000DisplayRRTODT33() else {
            throw XCTSkip("Missing ACES 1.3 HDR PQ1000 LUT resource")
        }

        let height = Int(ProcessInfo.processInfo.environment["METAVIS_ODT_PERF_HEIGHT"].flatMap(Int.init) ?? 2160)
        let frames = Int(ProcessInfo.processInfo.environment["METAVIS_ODT_PERF_FRAMES"].flatMap(Int.init) ?? 30)
        let warmup = 3

        let width = height * 16 / 9
        let quality = QualityProfile(name: "ODTPerf", fidelity: .high, resolutionHeight: height, colorDepth: 32)

        let engine = try MetalSimulationEngine()
        try await engine.configure()

        struct Variant {
            var label: String
            var lutData: Data
            var shaderName: String
        }

        let variants: [(title: String, v: Variant)] = [
            ("SDR", Variant(label: "SDR", lutData: sdrLUT, shaderName: "odt_acescg_to_rec709_studio")),
            ("HDR_PQ1000", Variant(label: "HDR_PQ1000", lutData: hdrLUT, shaderName: "odt_acescg_to_pq1000"))
        ]

        for (title, v) in variants {
            let source = RenderNode(name: "Macbeth", shader: "fx_macbeth")

            let lutODT = RenderNode(
                name: "ODT_LUT",
                shader: "lut_apply_3d_rgba16f",
                inputs: ["input": source.id],
                parameters: ["lut": .data(v.lutData)],
                output: RenderNode.OutputSpec(resolution: .full, pixelFormat: .rgba16Float)
            )
            let shaderODT = RenderNode(
                name: "ODT_Shader",
                shader: v.shaderName,
                inputs: ["input": source.id]
            )

            func run(graph: RenderGraph, odtNodeName: String) async throws -> [Double] {
                var samples: [Double] = []
                samples.reserveCapacity(frames)
                let request = RenderRequest(graph: graph, time: .zero, quality: quality, skipReadback: true)
                for i in 0..<(warmup + frames) {
                    if i == 0 {
                        print("[Perf][\(title)] Starting \(odtNodeName): warmup=\(warmup) frames=\(frames) (skipReadback=1)")
                    } else if i == warmup {
                        print("[Perf][\(title)] \(odtNodeName): warmup complete")
                    } else if i > warmup, ((i - warmup) % 10 == 0) {
                        print("[Perf][\(title)] \(odtNodeName): sample \(i - warmup)/\(frames)")
                    }
                    let result = try await engine.render(request: request, captureNodeTimings: true)
                    guard let report = result.metadata["nodeTimings"] else {
                        XCTFail("Missing nodeTimings in result metadata")
                        break
                    }
                    let timings = parseNodeTimings(report)
                    guard let odt = timings.first(where: { $0.name == odtNodeName }), let ms = odt.gpuMs else {
                        XCTFail("Missing GPU timing for node \(odtNodeName) in: \(report)")
                        break
                    }
                    if i >= warmup {
                        samples.append(ms)
                    }
                }
                return samples
            }

            let lutGraph = RenderGraph(nodes: [source, lutODT], rootNodeID: lutODT.id)
            let shaderGraph = RenderGraph(nodes: [source, shaderODT], rootNodeID: shaderODT.id)

            let lutMs = try await run(graph: lutGraph, odtNodeName: "ODT_LUT")
            let shaderMs = try await run(graph: shaderGraph, odtNodeName: "ODT_Shader")

            func stats(_ xs: [Double]) -> (mean: Double, p95: Double, min: Double, max: Double) {
                let mean = xs.reduce(0, +) / Double(max(xs.count, 1))
                return (mean, percentile(xs, 0.95), xs.min() ?? 0, xs.max() ?? 0)
            }

            let a = stats(lutMs)
            let b = stats(shaderMs)
            let speedup = (b.mean > 0) ? (a.mean / b.mean) : 0

            print(String(format: "[Perf][%s][%dx%d] LUT ODT GPU: mean=%.3fms p95=%.3fms (min=%.3f max=%.3f)",
                         (title as NSString).utf8String!, width, height, a.mean, a.p95, a.min, a.max))
            print(String(format: "[Perf][%s][%dx%d] Shader ODT GPU: mean=%.3fms p95=%.3fms (min=%.3f max=%.3f)",
                         (title as NSString).utf8String!, width, height, b.mean, b.p95, b.min, b.max))
            print(String(format: "[Perf][%s] LUT/Shader speedup (mean): %.2fx", (title as NSString).utf8String!, speedup))

            XCTAssertEqual(lutMs.count, frames)
            XCTAssertEqual(shaderMs.count, frames)
        }
    }
}
