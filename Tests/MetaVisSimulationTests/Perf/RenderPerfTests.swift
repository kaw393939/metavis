import XCTest
import CoreVideo
import MetaVisCore
import MetaVisGraphics
import MetaVisSimulation
import Foundation

final class RenderPerfTests: XCTestCase {

    private func isExtendedPerfEnabled() -> Bool {
        ProcessInfo.processInfo.environment["METAVIS_RUN_EXTENDED_PERF"] == "1"
    }

    private func perf360p() -> QualityProfile {
        QualityProfile(name: "Perf 360p", fidelity: .high, resolutionHeight: 360, colorDepth: 10)
    }

    private func perfProfile(height: Int) -> QualityProfile {
        QualityProfile(name: "Perf \(height)p", fidelity: .high, resolutionHeight: height, colorDepth: 10)
    }

    private func sweepHeights() -> [Int] {
        // Optional explicit override (comma-separated), e.g. "1080,2160,4320".
        if let raw = ProcessInfo.processInfo.environment["METAVIS_PERF_SWEEP_HEIGHTS"], !raw.isEmpty {
            let heights = raw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .compactMap { Int($0) }
                .filter { $0 > 0 }
            if !heights.isEmpty {
                return Array(Set(heights)).sorted()
            }
        }

        // Common 16:9 heights: 360p, 720p, 1080p, 2160p (4K), 4320p (8K)
        var heights = [360, 720, 1080, 2160]

        let maxH = Int(ProcessInfo.processInfo.environment["METAVIS_PERF_SWEEP_MAX_HEIGHT"] ?? "")
        if let maxH, maxH > 0 {
            heights = heights.filter { $0 <= maxH }
        }

        if ProcessInfo.processInfo.environment["METAVIS_RUN_PERF_8K"] == "1" {
            heights.append(4320)
        }
        return heights
    }

    private func sweepPolicyTiers() -> [RenderPolicyTier] {
        // Default: avoid multiplying sweep cost unless explicitly requested.
        if ProcessInfo.processInfo.environment["METAVIS_PERF_SWEEP_POLICIES"] != "1" {
            return [.creator]
        }

        if let raw = ProcessInfo.processInfo.environment["METAVIS_PERF_SWEEP_POLICY_TIERS"], !raw.isEmpty {
            let parts = raw.split(separator: ",").map { String($0) }
            let tiers = parts.compactMap { RenderPolicyTier.parse($0) }
            return tiers.isEmpty ? RenderPolicyTier.allCases : tiers
        }

        return RenderPolicyTier.allCases
    }

    private func framesForResolution(height: Int) -> Int {
        if let v = Int(ProcessInfo.processInfo.environment["METAVIS_PERF_FRAMES"] ?? ""), v > 0 {
            return v
        }
        switch height {
        case 0..<720: return 12
        case 720..<2160: return 8
        case 2160..<4320: return 4
        default: return 2
        }
    }

    private func sweepRepeats() -> Int {
        let raw = ProcessInfo.processInfo.environment["METAVIS_PERF_SWEEP_REPEATS"] ?? ""
        let n = Int(raw) ?? 1
        return max(1, min(50, n))
    }

    private func formatRepeatNote(repeats: Int, samples: [Double]) -> String {
        guard repeats > 1, !samples.isEmpty else { return "" }
        let minV = samples.min() ?? 0
        let maxV = samples.max() ?? 0
        let mean = samples.reduce(0, +) / Double(samples.count)
        let variance = samples.reduce(0.0) { $0 + pow($1 - mean, 2.0) } / Double(samples.count)
        let sd = sqrt(max(0.0, variance))
        return String(format: "repeats=%d mean=%.2fms sd=%.2f min=%.2f max=%.2f", repeats, mean, sd, minV, maxV)
    }

    private func estimateBytesRGBAHalf(width: Int, height: Int, textures: Int) -> UInt64 {
        let bytesPerPixel: UInt64 = 8 // RGBA16F
        return UInt64(width) * UInt64(height) * bytesPerPixel * UInt64(textures)
    }

    private func shouldSkipEstimatedMemory(label: String, width: Int, height: Int) -> (skip: Bool, reason: String?) {
        // Rough safety valve to avoid GPU/driver instability during huge allocations.
        // Can be overridden by setting METAVIS_PERF_DISABLE_ESTIMATE_SKIP=1.
        if ProcessInfo.processInfo.environment["METAVIS_PERF_DISABLE_ESTIMATE_SKIP"] == "1" {
            return (false, nil)
        }

        let maxMB = UInt64(ProcessInfo.processInfo.environment["METAVIS_PERF_MAX_EST_TEXTURE_MB"] ?? "") ?? 1500
        let maxBytes = maxMB * 1024 * 1024

        let textures: Int
        switch label {
        case "Render": textures = 2
        case "CompositorCrossfade": textures = 3
        case "BlurChain": textures = 4
        case "MaskedBlur": textures = 5
        case "ODTLUT": textures = 3
        default: textures = 4
        }
        let est = estimateBytesRGBAHalf(width: width, height: height, textures: textures)
        if est > maxBytes {
            return (true, "Estimated working set \(est / 1024 / 1024)MB exceeds cap \(maxMB)MB")
        }
        return (false, nil)
    }

    private func makeRGBAHalfPixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_64RGBAHalf,
            kCVPixelBufferMetalCompatibilityKey: true
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_64RGBAHalf, attrs as CFDictionary, &pixelBuffer)
        guard status == kCVReturnSuccess, let pb = pixelBuffer else {
            throw XCTSkip("Failed to create CVPixelBuffer (status=\(status))")
        }
        return pb
    }

    private func measureAvgMs(
        engine: MetalSimulationEngine,
        graph: RenderGraph,
        quality: QualityProfile,
        renderPolicy: RenderPolicyTier = .creator,
        frames: Int = 12,
        label: String
    ) async throws -> Double {
        let width = quality.resolutionHeight * 16 / 9
        let height = quality.resolutionHeight
        let pb = try makeRGBAHalfPixelBuffer(width: width, height: height)

        // Warm up pipelines + pool.
        try await engine.render(request: RenderRequest(graph: graph, time: .zero, quality: quality, renderPolicy: renderPolicy), to: pb)
        try await engine.render(request: RenderRequest(graph: graph, time: .zero, quality: quality, renderPolicy: renderPolicy), to: pb)

        let clock = ContinuousClock()
        let start = clock.now
        for i in 0..<frames {
            let t = Time(seconds: Double(i) / 24.0)
            try await engine.render(request: RenderRequest(graph: graph, time: t, quality: quality, renderPolicy: renderPolicy), to: pb)
        }
        let elapsed = clock.now - start
        let c = elapsed.components
        let seconds = Double(c.seconds) + (Double(c.attoseconds) / 1_000_000_000_000_000_000.0)
        let avgMs = (seconds / Double(frames)) * 1000.0

        if ProcessInfo.processInfo.environment["METAVIS_PERF_LOG"] == "1" {
            print(String(format: "[Perf] %@ avg %.2fms over %d frames (%dx%d)", label as NSString, avgMs, frames, width, height))
        }

        var e = PerfLogger.makeBaseEvent(
            suite: "RenderPerfTests",
            test: String(describing: #function),
            label: label,
            width: width,
            height: height,
            frames: frames
        )
        e.avgMs = avgMs
        PerfLogger.write(e)

        return avgMs
    }

    func test_render_frame_budget() async throws {
        let engine = try MetalSimulationEngine()
        try await engine.configure()

        let src = RenderNode(name: "SMPTE", shader: "fx_smpte_bars")
        let graph = RenderGraph(nodes: [src], rootNodeID: src.id)

        let quality = perf360p()
        let width = quality.resolutionHeight * 16 / 9
        let height = quality.resolutionHeight

        let pb = try makeRGBAHalfPixelBuffer(width: width, height: height)

        let request = RenderRequest(graph: graph, time: .zero, quality: quality)

        // Warm up pipelines + pool.
        try await engine.render(request: request, to: pb)
        try await engine.render(request: request, to: pb)

        let frames = 12
        let clock = ContinuousClock()
        let start = clock.now
        for i in 0..<frames {
            let t = Time(seconds: Double(i) / 24.0)
            let req = RenderRequest(graph: graph, time: t, quality: quality)
            try await engine.render(request: req, to: pb)
        }
        let elapsed = clock.now - start
        let c = elapsed.components
        let seconds = Double(c.seconds) + (Double(c.attoseconds) / 1_000_000_000_000_000_000.0)
        let avgMs = (seconds / Double(frames)) * 1000.0

        if ProcessInfo.processInfo.environment["METAVIS_PERF_LOG"] == "1" {
            print(String(format: "[Perf] Render avg %.2fms over %d frames (%dx%d)", avgMs, frames, width, height))
        }

        var e = PerfLogger.makeBaseEvent(
            suite: "RenderPerfTests",
            test: "test_render_frame_budget",
            label: "Render",
            width: width,
            height: height,
            frames: frames
        )
        e.avgMs = avgMs
        PerfLogger.write(e)

        let isCI = ProcessInfo.processInfo.environment["CI"] == "true"
        let budgetMs = Double(ProcessInfo.processInfo.environment["METAVIS_RENDER_FRAME_BUDGET_MS"] ?? "") ?? (isCI ? 800.0 : 400.0)

        XCTAssertLessThanOrEqual(avgMs, budgetMs, String(format: "Avg render %.2fms exceeded budget %.2fms", avgMs, budgetMs))
    }

    func test_render_perf_sweep_common_resolutions_opt_in() async throws {
        guard ProcessInfo.processInfo.environment["METAVIS_RUN_PERF_SWEEP"] == "1" else {
            throw XCTSkip("Set METAVIS_RUN_PERF_SWEEP=1 to run resolution sweep")
        }

        // Build graphs once; vary only output resolution.
        let src = RenderNode(name: "SMPTE", shader: "fx_smpte_bars")
        let baselineGraph = RenderGraph(nodes: [src], rootNodeID: src.id)

        let clipA = RenderNode(name: "A", shader: "fx_smpte_bars")
        let clipB = RenderNode(name: "B", shader: "source_test_color")
        let xfade = RenderNode(
            name: "Crossfade",
            shader: "compositor_crossfade",
            inputs: ["clipA": clipA.id, "clipB": clipB.id],
            parameters: ["mix": .float(0.5)]
        )
        let compositorGraph = RenderGraph(nodes: [clipA, clipB, xfade], rootNodeID: xfade.id)

        // Resolution-aware blur chain (mandated): downsample -> blur -> upscale.
        let down = RenderNode(
            name: "Downsample",
            shader: "resize_bilinear_rgba16f",
            inputs: ["input": src.id],
            output: RenderNode.OutputSpec(resolution: .half, pixelFormat: .rgba16Float)
        )
        let blur = RenderNode(
            name: "Blur",
            shader: "fx_mip_blur",
            inputs: ["input": down.id],
            parameters: ["radius": .float(6)],
            output: RenderNode.OutputSpec(resolution: .half, pixelFormat: .rgba16Float)
        )
        let up = RenderNode(
            name: "Upscale",
            shader: "resize_bicubic_rgba16f",
            inputs: ["input": blur.id],
            output: RenderNode.OutputSpec(resolution: .full, pixelFormat: .rgba16Float)
        )
        let blurGraph = RenderGraph(nodes: [src, down, blur, up], rootNodeID: up.id)

        let source = RenderNode(name: "Source", shader: "source_test_color")
        let mask = RenderNode(name: "Mask", shader: "clear_color")
        let downMasked = RenderNode(
            name: "Downsample",
            shader: "resize_bilinear_rgba16f",
            inputs: ["input": source.id],
            output: RenderNode.OutputSpec(resolution: .half, pixelFormat: .rgba16Float)
        )
        let maskedBlur = RenderNode(
            name: "MaskedBlur",
            shader: "fx_masked_blur",
            inputs: [
                "input": source.id,
                "blur_base": downMasked.id,
                "mask": mask.id
            ],
            parameters: [
                "radius": .float(12.0),
                "threshold": .float(1.0)
            ],
            output: RenderNode.OutputSpec(resolution: .full, pixelFormat: .rgba16Float)
        )
        let maskedBlurGraph = RenderGraph(nodes: [source, mask, downMasked, maskedBlur], rootNodeID: maskedBlur.id)

        // ACES ODT LUT application (tracks LUT apply cost).
        let odtLUTGraph: RenderGraph? = {
            guard let lutData = LUTResources.aces13SDRSRGBDisplayRRTODT33() else { return nil }
            let macbeth = RenderNode(name: "Macbeth", shader: "fx_macbeth")
            let odt = RenderNode(
                name: "ODTLUT",
                shader: "lut_apply_3d_rgba16f",
                inputs: ["input": macbeth.id],
                parameters: ["lut": .data(lutData)],
                output: RenderNode.OutputSpec(resolution: .full, pixelFormat: .rgba16Float)
            )
            return RenderGraph(nodes: [macbeth, odt], rootNodeID: odt.id)
        }()

        // Measure and Log
        let engine = try MetalSimulationEngine()
        try await engine.configure()
        let runID = PerfLogger.runID()
        var summary: [String] = []

        let qcEnabled = PerfColorBaselines.isEnabled()
        var qcBaselines = qcEnabled ? PerfColorBaselines.loadBaselines() : [:]
        var qcBaselinesDirty = false

        let tiers = sweepPolicyTiers()

        summary.append("Env:")
        summary.append("- METAVIS_RUN_PERF_SWEEP=1")
        summary.append("- METAVIS_RUN_PERF_8K=\(ProcessInfo.processInfo.environment["METAVIS_RUN_PERF_8K"] ?? "0")")
        summary.append("- METAVIS_PERF_SWEEP_MAX_HEIGHT=\(ProcessInfo.processInfo.environment["METAVIS_PERF_SWEEP_MAX_HEIGHT"] ?? "")")
        summary.append("- METAVIS_PERF_SWEEP_REPEATS=\(sweepRepeats())")
        summary.append("- METAVIS_PERF_SWEEP_POLICIES=\(ProcessInfo.processInfo.environment["METAVIS_PERF_SWEEP_POLICIES"] ?? "0")")
        summary.append("- METAVIS_PERF_SWEEP_POLICY_TIERS=\(ProcessInfo.processInfo.environment["METAVIS_PERF_SWEEP_POLICY_TIERS"] ?? "")")
        summary.append("- resolved_policy_tiers=\(tiers.map { $0.rawValue }.joined(separator: ","))")
        summary.append("")
        summary.append("| Label | Resolution | Frames | Avg (ms) | Status | Note |")
        summary.append("|---|---:|---:|---:|---|---|")

        func runOne(label: String, graph: RenderGraph, quality: QualityProfile, tier: RenderPolicyTier) async {
            let width = quality.resolutionHeight * 16 / 9
            let height = quality.resolutionHeight
            let frames = framesForResolution(height: height)
            let repeats = sweepRepeats()

            let labelWithTier = "\(label)@\(tier.rawValue)"

            let (skip, reason) = shouldSkipEstimatedMemory(label: label, width: width, height: height)
            if skip {
                var e = PerfLogger.makeBaseEvent(
                    suite: "RenderPerfTests",
                    test: "test_render_perf_sweep_common_resolutions_opt_in",
                    label: labelWithTier,
                    width: width,
                    height: height,
                    frames: frames
                )
                e.status = .skipped
                e.message = reason
                PerfLogger.write(e)
                summary.append("| \(labelWithTier) | \(width)x\(height) | \(frames) |  | skipped | \(reason ?? "") |")
                return
            }

            do {
                var samples: [Double] = []
                samples.reserveCapacity(repeats)
                for r in 0..<repeats {
                    let avg = try await measureAvgMs(
                        engine: engine,
                        graph: graph,
                        quality: quality,
                        renderPolicy: tier,
                        frames: frames,
                        label: repeats > 1 ? "\(labelWithTier)#\(r+1)" : labelWithTier
                    )
                    samples.append(avg)
                }

                let avg = samples.reduce(0, +) / Double(samples.count)

                var note = formatRepeatNote(repeats: repeats, samples: samples)
                if label == "BlurChain",
                   height == 4320,
                   ProcessInfo.processInfo.environment["METAVIS_PERF_BLUR_BREAKDOWN"] == "1" {
                    // One diagnostic frame to attribute cost across nodes.
                    let pb = try makeRGBAHalfPixelBuffer(width: width, height: height)
                    try await engine.render(
                        request: RenderRequest(graph: graph, time: .zero, quality: quality, renderPolicy: tier),
                        to: pb,
                        captureNodeTimings: true
                    )
                    if let report = await engine.lastNodeTimingReport {
                        let breakdown = report
                            .replacingOccurrences(of: "|", with: ";")
                            .replacingOccurrences(of: "\n", with: " ")
                        if note.isEmpty {
                            note = breakdown
                        } else {
                            note = note + " ; " + breakdown
                        }
                    }
                }

                if label == "MaskedBlur",
                   height == 4320,
                   ProcessInfo.processInfo.environment["METAVIS_PERF_MASKEDBLUR_BREAKDOWN"] == "1" {
                    // One diagnostic frame to attribute cost across nodes.
                    let pb = try makeRGBAHalfPixelBuffer(width: width, height: height)
                    try await engine.render(
                        request: RenderRequest(graph: graph, time: .zero, quality: quality, renderPolicy: tier),
                        to: pb,
                        captureNodeTimings: true
                    )
                    if let report = await engine.lastNodeTimingReport {
                        let breakdown = report
                            .replacingOccurrences(of: "|", with: ";")
                            .replacingOccurrences(of: "\n", with: " ")
                        if note.isEmpty {
                            note = breakdown
                        } else {
                            note = note + " ; " + breakdown
                        }
                    }
                }
                // Optional QC: compute a lightweight fingerprint from a single rendered frame.
                if qcEnabled {
                    do {
                        let pb = try makeRGBAHalfPixelBuffer(width: width, height: height)
                        try await engine.render(
                            request: RenderRequest(graph: graph, time: .zero, quality: quality, renderPolicy: tier),
                            to: pb
                        )

                        if let fp = PerfColorBaselines.computeFingerprint(pixelBuffer: pb) {
                            let key = PerfColorBaselines.baselineKey(
                                suite: "RenderPerfTests",
                                baselineLabel: labelWithTier,
                                width: width,
                                height: height,
                                policy: tier.rawValue
                            )

                            if let baseline = qcBaselines[key] {
                                let d = PerfColorBaselines.distance(fp, baseline)
                                let maxD = PerfColorBaselines.maxDistance()
                                let status = (d <= maxD) ? "ok" : "drift"
                                if note.isEmpty {
                                    note = String(format: "qc=%@ d=%.4f max=%.4f", status, d, maxD)
                                } else {
                                    note = note + String(format: " ; qc=%@ d=%.4f max=%.4f", status, d, maxD)
                                }

                                if PerfLogger.isEnabled() {
                                    var e = PerfLogger.makeBaseEvent(
                                        suite: "RenderPerfTests",
                                        test: "test_render_perf_sweep_common_resolutions_opt_in",
                                        label: labelWithTier,
                                        width: width,
                                        height: height,
                                        frames: frames
                                    )
                                    e.avgMs = avg
                                    e.qcFingerprintHash = fp.hash
                                    e.qcMeanRGB = fp.meanRGB
                                    e.qcStdRGB = fp.stdRGB
                                    e.qcSamples = fp.samples
                                    e.qcBaselineDistance = d
                                    e.qcBaselineStatus = status
                                    PerfLogger.write(e)
                                }

                                if status != "ok", PerfColorBaselines.isStrict() {
                                    XCTFail("QC fingerprint drift for \(labelWithTier) \(width)x\(height): d=\(d) > max=\(maxD)")
                                }
                            } else if PerfColorBaselines.isWriteEnabled() {
                                qcBaselines[key] = fp
                                qcBaselinesDirty = true
                                if note.isEmpty {
                                    note = "qc=baseline_written"
                                } else {
                                    note = note + " ; qc=baseline_written"
                                }
                            } else {
                                if note.isEmpty {
                                    note = "qc=baseline_missing"
                                } else {
                                    note = note + " ; qc=baseline_missing"
                                }
                            }
                        }
                    } catch {
                        if note.isEmpty {
                            note = "qc=error"
                        } else {
                            note = note + " ; qc=error"
                        }
                    }
                }

                summary.append(String(format: "| %@ | %dx%d | %d | %.2f | ok | %@ |", labelWithTier, width, height, frames, avg, note))
            } catch {
                var e = PerfLogger.makeBaseEvent(
                    suite: "RenderPerfTests",
                    test: "test_render_perf_sweep_common_resolutions_opt_in",
                    label: labelWithTier,
                    width: width,
                    height: height,
                    frames: frames
                )
                e.status = .failed
                e.message = String(describing: error)
                PerfLogger.write(e)
                summary.append("| \(labelWithTier) | \(width)x\(height) | \(frames) |  | failed | \(String(describing: error)) |")

                if ProcessInfo.processInfo.environment["METAVIS_PERF_SWEEP_STRICT"] == "1" {
                    XCTFail("Perf sweep failed for \(label) at \(width)x\(height): \(error)")
                }
            }
        }

        for h in sweepHeights() {
            let q = perfProfile(height: h)
            for tier in tiers {
                await runOne(label: "Render", graph: baselineGraph, quality: q, tier: tier)
                await runOne(label: "CompositorCrossfade", graph: compositorGraph, quality: q, tier: tier)
                await runOne(label: "BlurChain", graph: blurGraph, quality: q, tier: tier)
                await runOne(label: "MaskedBlur", graph: maskedBlurGraph, quality: q, tier: tier)
                if let odtLUTGraph {
                    await runOne(label: "ODTLUT", graph: odtLUTGraph, quality: q, tier: tier)
                }
            }
        }

        if qcBaselinesDirty {
            PerfColorBaselines.saveBaselines(qcBaselines)
        }

        PerfLogger.writeMarkdownSummary(summary.joined(separator: "\n"), fileName: "perf_sweep_\(runID).md")
    }

    func test_render_perf_blur_chain_opt_in() async throws {
        guard isExtendedPerfEnabled() else {
            throw XCTSkip("Set METAVIS_RUN_EXTENDED_PERF=1 to run extended perf tests")
        }

        let engine = try MetalSimulationEngine()
        try await engine.configure()

        let src = RenderNode(name: "SMPTE", shader: "fx_smpte_bars")
        let blur = RenderNode(
            name: "Blur",
            shader: "fx_mip_blur",
            inputs: ["input": src.id],
            parameters: ["radius": .float(6)]
        )

        let graph = RenderGraph(nodes: [src, blur], rootNodeID: blur.id)
        let avgMs = try await measureAvgMs(engine: engine, graph: graph, quality: perf360p(), label: "BlurChain")

        let budgetMs = Double(ProcessInfo.processInfo.environment["METAVIS_RENDER_FRAME_BUDGET_MS_EXTENDED"] ?? "") ?? 1000.0
        XCTAssertLessThanOrEqual(avgMs, budgetMs, String(format: "Avg render %.2fms exceeded extended budget %.2fms", avgMs, budgetMs))
    }

    func test_render_perf_masked_blur_opt_in() async throws {
        guard isExtendedPerfEnabled() else {
            throw XCTSkip("Set METAVIS_RUN_EXTENDED_PERF=1 to run extended perf tests")
        }

        let engine = try MetalSimulationEngine()
        try await engine.configure()

        let source = RenderNode(name: "Source", shader: "source_test_color")
        let mask = RenderNode(name: "Mask", shader: "clear_color")
        let down = RenderNode(
            name: "Downsample",
            shader: "resize_bilinear_rgba16f",
            inputs: ["input": source.id],
            output: RenderNode.OutputSpec(resolution: .half, pixelFormat: .rgba16Float)
        )
        let maskedBlur = RenderNode(
            name: "MaskedBlur",
            shader: "fx_masked_blur",
            inputs: [
                "input": source.id,
                "blur_base": down.id,
                "mask": mask.id
            ],
            parameters: [
                "radius": .float(12.0),
                "threshold": .float(1.0)
            ],
            output: RenderNode.OutputSpec(resolution: .full, pixelFormat: .rgba16Float)
        )

        let graph = RenderGraph(nodes: [source, mask, down, maskedBlur], rootNodeID: maskedBlur.id)
        let avgMs = try await measureAvgMs(engine: engine, graph: graph, quality: perf360p(), label: "MaskedBlur")

        let budgetMs = Double(ProcessInfo.processInfo.environment["METAVIS_RENDER_FRAME_BUDGET_MS_EXTENDED"] ?? "") ?? 1000.0
        XCTAssertLessThanOrEqual(avgMs, budgetMs, String(format: "Avg render %.2fms exceeded extended budget %.2fms", avgMs, budgetMs))
    }

    func test_render_perf_compositor_crossfade_opt_in() async throws {
        guard isExtendedPerfEnabled() else {
            throw XCTSkip("Set METAVIS_RUN_EXTENDED_PERF=1 to run extended perf tests")
        }

        let engine = try MetalSimulationEngine()
        try await engine.configure()

        let clipA = RenderNode(name: "A", shader: "fx_smpte_bars")
        let clipB = RenderNode(name: "B", shader: "source_test_color")
        let xfade = RenderNode(
            name: "Crossfade",
            shader: "compositor_crossfade",
            inputs: ["clipA": clipA.id, "clipB": clipB.id],
            parameters: ["mix": .float(0.5)]
        )

        let graph = RenderGraph(nodes: [clipA, clipB, xfade], rootNodeID: xfade.id)
        let avgMs = try await measureAvgMs(engine: engine, graph: graph, quality: perf360p(), label: "CompositorCrossfade")

        let budgetMs = Double(ProcessInfo.processInfo.environment["METAVIS_RENDER_FRAME_BUDGET_MS_EXTENDED"] ?? "") ?? 1000.0
        XCTAssertLessThanOrEqual(avgMs, budgetMs, String(format: "Avg render %.2fms exceeded extended budget %.2fms", avgMs, budgetMs))
    }
}
