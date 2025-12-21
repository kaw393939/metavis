import XCTest
import MetaVisCore
import MetaVisSimulation

#if canImport(Darwin)
import Darwin
#endif

#if canImport(Darwin.Mach)
import Darwin.Mach
#endif

private enum ProcessMemory {
    static func residentSizeBytes() -> UInt64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return nil }
        return UInt64(info.resident_size)
    }

    /// Returns the peak resident set size (RSS) since process start, if available.
    static func residentSizePeakBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return nil }
        return UInt64(info.resident_size_peak)
    }
}

final class RenderMemoryPerfTests: XCTestCase {

    private func perf360p() -> QualityProfile {
        QualityProfile(name: "Perf 360p", fidelity: .high, resolutionHeight: 360, colorDepth: 10)
    }

    func test_render_peak_rss_delta_budget() async throws {
        guard let startPeak = ProcessMemory.residentSizePeakBytes() else {
            throw XCTSkip("task_vm_info resident_size_peak unavailable")
        }

        let engine = try MetalSimulationEngine()
        try await engine.configure()

        // Multi-pass-ish graph: SMPTE -> blur_h -> blur_v
        let src = RenderNode(name: "SMPTE", shader: "fx_smpte_bars")
        let blurH = RenderNode(
            name: "BlurH",
            shader: "fx_blur_h",
            inputs: ["input": src.id],
            parameters: ["radius": .float(6)]
        )
        let blurV = RenderNode(
            name: "BlurV",
            shader: "fx_blur_v",
            inputs: ["input": blurH.id],
            parameters: ["radius": .float(6)]
        )

        let graph = RenderGraph(nodes: [src, blurH, blurV], rootNodeID: blurV.id)
        let quality = perf360p()

        // Warm up.
        _ = try await engine.render(request: RenderRequest(graph: graph, time: .zero, quality: quality))
        _ = try await engine.render(request: RenderRequest(graph: graph, time: .zero, quality: quality))

        for i in 0..<24 {
            let t = Time(seconds: Double(i) / 24.0)
            _ = try await engine.render(request: RenderRequest(graph: graph, time: t, quality: quality))
        }

        guard let endPeak = ProcessMemory.residentSizePeakBytes() else {
            throw XCTSkip("task_vm_info resident_size_peak unavailable after render")
        }

        let isCI = ProcessInfo.processInfo.environment["CI"] == "true"
        let budgetMB = UInt64(ProcessInfo.processInfo.environment["METAVIS_RENDER_PEAK_RSS_DELTA_MB"] ?? "") ?? (isCI ? 2048 : 1024)
        let budgetBytes = budgetMB * 1024 * 1024

        let deltaPeak = endPeak > startPeak ? (endPeak - startPeak) : 0
        XCTAssertLessThanOrEqual(
            deltaPeak,
            budgetBytes,
            "Peak RSS delta exceeded budget: delta=\(deltaPeak) bytes, budget=\(budgetBytes) bytes (set METAVIS_RENDER_PEAK_RSS_DELTA_MB to override)"
        )

        // Secondary sanity: current RSS should be readable when supported.
        _ = ProcessMemory.residentSizeBytes()
    }
}
