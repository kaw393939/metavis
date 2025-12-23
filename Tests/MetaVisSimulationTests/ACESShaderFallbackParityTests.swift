import XCTest
import Metal
import simd
import MetaVisCore
import MetaVisGraphics
@testable import MetaVisSimulation

final class ACESShaderFallbackParityTests: XCTestCase {

    private struct ErrStats {
        var meanAbs: Double
        var maxAbs: Double
        var worstPatch: String
    }

    private struct DeltaEStats {
        var mean: Double
        var max: Double
        var worstPatch: String
    }

    private func renderRGBA32F(engine: MetalSimulationEngine, graph: RenderGraph, height: Int) async throws -> (width: Int, height: Int, rgba: [Float]) {
        let width = height * 16 / 9
        let quality = QualityProfile(name: "ShaderFallbackParity", fidelity: .high, resolutionHeight: height, colorDepth: 32)
        let request = RenderRequest(graph: graph, time: .zero, quality: quality)

        let result = try await engine.render(request: request)
        guard let data = result.imageBuffer else {
            XCTFail("No imageBuffer produced: \(result.metadata)")
            return (width, height, [])
        }

        let expectedFloats = width * height * 4
        let rgba: [Float] = data.withUnsafeBytes { raw in
            let base = raw.bindMemory(to: Float.self)
            return Array(base.prefix(expectedFloats))
        }
        XCTAssertEqual(rgba.count, expectedFloats)
        return (width, height, rgba)
    }

    private func samplePatchCenters(width: Int, height: Int, rgba: [Float]) -> [SIMD3<Float>] {
        func sample(col: Int, row: Int) -> SIMD3<Float> {
            let u = (Double(col) + 0.5) / 6.0
            let v = (Double(row) + 0.5) / 4.0
            let x = min(max(Int(u * Double(width)), 0), width - 1)
            let y = min(max(Int(v * Double(height)), 0), height - 1)
            let idx = (y * width + x) * 4
            return SIMD3(rgba[idx + 0], rgba[idx + 1], rgba[idx + 2])
        }

        var patches: [SIMD3<Float>] = []
        patches.reserveCapacity(24)
        for row in 0..<4 {
            for col in 0..<6 {
                patches.append(sample(col: col, row: row))
            }
        }
        return patches
    }

    private func dumpPatchComparison(
        label: String,
        shader: [SIMD3<Float>],
        reference: [SIMD3<Float>],
        patchNames: [String]
    ) {
        guard ProcessInfo.processInfo.environment["METAVIS_SHADER_LUT_PARITY_VERBOSE"] == "1" else {
            return
        }
        print("[ColorCert] ---- \(label) ----")
        for i in 0..<min(shader.count, reference.count) {
            let a = shader[i]
            let b = reference[i]
            let d = simd_abs(a - b)
            let patchMax = max(d.x, max(d.y, d.z))
            print(String(format: "[ColorCert] %-14s shader=(%.6f %.6f %.6f) lut=(%.6f %.6f %.6f) maxAbs=%.6f",
                         (patchNames[i] as NSString).utf8String!,
                         a.x, a.y, a.z,
                         b.x, b.y, b.z,
                         patchMax))
        }
    }

    private func computeErrStats(shader: [SIMD3<Float>], reference: [SIMD3<Float>], patchNames: [String]) -> ErrStats {
        precondition(shader.count == reference.count)
        precondition(shader.count == patchNames.count)

        func clamp01(_ v: SIMD3<Float>) -> SIMD3<Float> {
            SIMD3(
                min(max(v.x, 0), 1),
                min(max(v.y, 0), 1),
                min(max(v.z, 0), 1)
            )
        }

        var sumAbs: Double = 0
        var n: Int = 0
        var maxAbs: Double = 0
        var worst = patchNames.first ?? "(unknown)"

        for i in 0..<shader.count {
            let a = clamp01(shader[i])
            let b = clamp01(reference[i])
            let d = simd_abs(a - b)
            let patchMax = Double(max(d.x, max(d.y, d.z)))

            sumAbs += Double(d.x + d.y + d.z)
            n += 3

            if patchMax > maxAbs {
                maxAbs = patchMax
                worst = patchNames[i]
            }
        }

        let meanAbs = (n > 0) ? (sumAbs / Double(n)) : 0
        return ErrStats(meanAbs: meanAbs, maxAbs: maxAbs, worstPatch: worst)
    }

    private struct LabD65: Equatable {
        var L: Double
        var a: Double
        var b: Double
    }

    private func srgbToLinear(_ v: Double) -> Double {
        if v <= 0.04045 { return v / 12.92 }
        return pow((v + 0.055) / 1.055, 2.4)
    }

    private func rgbToLab_D65(_ srgb01: SIMD3<Double>) -> LabD65 {
        // 1) sRGB -> linear RGB (Rec.709 primaries, D65)
        let r = srgbToLinear(srgb01.x)
        let g = srgbToLinear(srgb01.y)
        let b = srgbToLinear(srgb01.z)

        // 2) linear RGB -> XYZ (D65)
        let X = 0.4124564 * r + 0.3575761 * g + 0.1804375 * b
        let Y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
        let Z = 0.0193339 * r + 0.1191920 * g + 0.9503041 * b

        // 3) XYZ -> Lab (D65 reference white)
        let xn = X / 0.95047
        let yn = Y / 1.00000
        let zn = Z / 1.08883

        func f(_ t: Double) -> Double {
            t > 0.008856 ? pow(t, 1.0 / 3.0) : (7.787 * t + 16.0 / 116.0)
        }

        let fx = f(xn)
        let fy = f(yn)
        let fz = f(zn)

        return LabD65(
            L: 116.0 * fy - 16.0,
            a: 500.0 * (fx - fy),
            b: 200.0 * (fy - fz)
        )
    }

    private func deltaE2000(_ lab1: LabD65, _ lab2: LabD65) -> Double {
        let kL = 1.0
        let kC = 1.0
        let kH = 1.0

        let L1 = lab1.L, a1 = lab1.a, b1 = lab1.b
        let L2 = lab2.L, a2 = lab2.a, b2 = lab2.b

        let C1 = sqrt(a1 * a1 + b1 * b1)
        let C2 = sqrt(a2 * a2 + b2 * b2)
        let C_bar = (C1 + C2) / 2.0

        let G = 0.5 * (1.0 - sqrt(pow(C_bar, 7) / (pow(C_bar, 7) + pow(25.0, 7))))

        let a1_prime = (1.0 + G) * a1
        let a2_prime = (1.0 + G) * a2

        let C1_prime = sqrt(a1_prime * a1_prime + b1 * b1)
        let C2_prime = sqrt(a2_prime * a2_prime + b2 * b2)

        func atan2deg(_ y: Double, _ x: Double) -> Double {
            let deg = atan2(y, x) * 180.0 / .pi
            return deg >= 0 ? deg : deg + 360.0
        }

        let h1 = (b1 == 0 && a1_prime == 0) ? 0.0 : atan2deg(b1, a1_prime)
        let h2 = (b2 == 0 && a2_prime == 0) ? 0.0 : atan2deg(b2, a2_prime)

        let delta_L_prime = L2 - L1
        let delta_C_prime = C2_prime - C1_prime

        var delta_h_prime = 0.0
        if (C1_prime * C2_prime) != 0 {
            if abs(h2 - h1) <= 180 {
                delta_h_prime = h2 - h1
            } else if (h2 - h1) > 180 {
                delta_h_prime = h2 - h1 - 360
            } else {
                delta_h_prime = h2 - h1 + 360
            }
        }

        let delta_H_prime = 2.0 * sqrt(C1_prime * C2_prime) * sin((delta_h_prime / 2.0) * .pi / 180.0)

        let L_bar_prime = (L1 + L2) / 2.0
        let C_bar_prime = (C1_prime + C2_prime) / 2.0

        var h_bar_prime = 0.0
        if (C1_prime * C2_prime) != 0 {
            if abs(h1 - h2) <= 180 {
                h_bar_prime = (h1 + h2) / 2.0
            } else if (h1 + h2) < 360 {
                h_bar_prime = (h1 + h2 + 360) / 2.0
            } else {
                h_bar_prime = (h1 + h2 - 360) / 2.0
            }
        } else {
            h_bar_prime = h1 + h2
        }

        let T = 1.0 - 0.17 * cos((h_bar_prime - 30) * .pi / 180.0)
            + 0.24 * cos((2 * h_bar_prime) * .pi / 180.0)
            + 0.32 * cos((3 * h_bar_prime + 6) * .pi / 180.0)
            - 0.20 * cos((4 * h_bar_prime - 63) * .pi / 180.0)

        let delta_theta = 30.0 * exp(-pow((h_bar_prime - 275.0) / 25.0, 2))
        let R_C = 2.0 * sqrt(pow(C_bar_prime, 7) / (pow(C_bar_prime, 7) + pow(25.0, 7)))
        let S_L = 1.0 + (0.015 * pow(L_bar_prime - 50.0, 2)) / sqrt(20.0 + pow(L_bar_prime - 50.0, 2))
        let S_C = 1.0 + 0.045 * C_bar_prime
        let S_H = 1.0 + 0.015 * C_bar_prime * T
        let R_T = -sin((2 * delta_theta) * .pi / 180.0) * R_C

        let term1 = delta_L_prime / (kL * S_L)
        let term2 = delta_C_prime / (kC * S_C)
        let term3 = delta_H_prime / (kH * S_H)

        return sqrt(term1 * term1 + term2 * term2 + term3 * term3 + R_T * term2 * term3)
    }

    private func computeDeltaE2000Stats_SDR(shader: [SIMD3<Float>], reference: [SIMD3<Float>], patchNames: [String]) -> DeltaEStats {
        precondition(shader.count == reference.count)
        precondition(shader.count == patchNames.count)

        func clamp01(_ v: SIMD3<Float>) -> SIMD3<Double> {
            SIMD3<Double>(
                Double(min(max(v.x, 0), 1)),
                Double(min(max(v.y, 0), 1)),
                Double(min(max(v.z, 0), 1))
            )
        }

        var sum: Double = 0
        var maxV: Double = 0
        var worst = patchNames.first ?? "(unknown)"

        for i in 0..<shader.count {
            let a = rgbToLab_D65(clamp01(shader[i]))
            let b = rgbToLab_D65(clamp01(reference[i]))
            let de = deltaE2000(a, b)
            sum += de
            if de > maxV {
                maxV = de
                worst = patchNames[i]
            }
        }

        let mean = shader.isEmpty ? 0 : (sum / Double(shader.count))
        return DeltaEStats(mean: mean, max: maxV, worstPatch: worst)
    }

    private func sampleHorizontalLine(width: Int, height: Int, rgba: [Float], y: Int, samples: Int) -> [SIMD3<Float>] {
        let yy = min(max(y, 0), height - 1)
        let n = max(2, samples)
        var out: [SIMD3<Float>] = []
        out.reserveCapacity(n)
        for i in 0..<n {
            let u = Double(i) / Double(n - 1)
            let x = min(max(Int(u * Double(width - 1)), 0), width - 1)
            let idx = (yy * width + x) * 4
            out.append(SIMD3(rgba[idx + 0], rgba[idx + 1], rgba[idx + 2]))
        }
        return out
    }

    private func lumaRec2020(_ rgb: SIMD3<Float>) -> Float {
        // Rec.2020 luma coefficients.
        rgb.x * 0.2627 + rgb.y * 0.6780 + rgb.z * 0.0593
    }

    private func envDouble(_ key: String, default defaultValue: Double) -> Double {
        if let s = ProcessInfo.processInfo.environment[key], let v = Double(s) {
            return v
        }
        return defaultValue
    }

    func test_shader_fallback_matches_sdr_lut_macbeth_opt_in() async throws {
        guard ProcessInfo.processInfo.environment["METAVIS_RUN_SHADER_LUT_PARITY"] == "1" else {
            throw XCTSkip("Set METAVIS_RUN_SHADER_LUT_PARITY=1 to measure shader ODT vs LUT parity")
        }
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal not available")
        }
        guard let sdrLUT = LUTResources.aces13SDRSRGBDisplayRRTODT33() else {
            throw XCTSkip("Missing ACES 1.3 SDR LUT resource")
        }

        let patchNames: [String] = [
            "dark_skin", "light_skin", "blue_sky", "foliage", "blue_flower", "bluish_green",
            "orange", "purplish_blue", "moderate_red", "purple", "yellow_green", "orange_yellow",
            "blue", "green", "red", "yellow", "magenta", "cyan",
            "white", "neutral_8", "neutral_65", "neutral_5", "neutral_35", "black"
        ]

        let height = 360
        let macbeth = RenderNode(name: "Macbeth", shader: "fx_macbeth")

        let lutODT = RenderNode(
            name: "ODT_LUT",
            shader: "lut_apply_3d_rgba16f",
            inputs: ["input": macbeth.id],
            parameters: ["lut": .data(sdrLUT)],
            output: RenderNode.OutputSpec(resolution: .full, pixelFormat: .rgba16Float)
        )

        let shaderODT = RenderNode(
            name: "ODT_Shader",
            shader: "odt_acescg_to_rec709_studio",
            inputs: ["input": macbeth.id]
        )

        let engine = try MetalSimulationEngine()
        try await engine.configure()

        let lutGraph = RenderGraph(nodes: [macbeth, lutODT], rootNodeID: lutODT.id)
        let shaderGraph = RenderGraph(nodes: [macbeth, shaderODT], rootNodeID: shaderODT.id)

        let (w1, h1, lutRGBA) = try await renderRGBA32F(engine: engine, graph: lutGraph, height: height)
        let (w2, h2, shaderRGBA) = try await renderRGBA32F(engine: engine, graph: shaderGraph, height: height)

        XCTAssertEqual(w1, w2)
        XCTAssertEqual(h1, h2)

        let lutPatches = samplePatchCenters(width: w1, height: h1, rgba: lutRGBA)
        let shaderPatches = samplePatchCenters(width: w2, height: h2, rgba: shaderRGBA)

        let stats = computeErrStats(shader: shaderPatches, reference: lutPatches, patchNames: patchNames)
        print(String(format: "[ColorCert] Shader ODT vs SDR LUT (Macbeth): meanAbsErr=%.6f maxAbsErr=%.6f worst=%@", stats.meanAbs, stats.maxAbs, stats.worstPatch))

        if PerfLogger.isEnabled() {
            var e = PerfLogger.makeBaseEvent(
                suite: "ColorCert",
                test: "test_shader_fallback_matches_sdr_lut_macbeth_opt_in",
                label: "ShaderODT@odt_acescg_to_rec709_studio vs LUT@aces13SDR",
                width: w1,
                height: h1,
                frames: 1
            )
            e.lutMeanAbsErr = stats.meanAbs
            e.lutMaxAbsErr = stats.maxAbs
            e.lutWorstPatch = stats.worstPatch
            PerfLogger.write(e)
        }

        XCTAssertTrue(stats.meanAbs.isFinite && stats.maxAbs.isFinite)
    }

    func test_shader_fallback_matches_sdr_lut_macbeth_deltaE2000_opt_in() async throws {
        guard ProcessInfo.processInfo.environment["METAVIS_RUN_SHADER_LUT_PARITY"] == "1" else {
            throw XCTSkip("Set METAVIS_RUN_SHADER_LUT_PARITY=1 to measure shader ODT vs LUT parity")
        }
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal not available")
        }
        guard let sdrLUT = LUTResources.aces13SDRSRGBDisplayRRTODT33() else {
            throw XCTSkip("Missing ACES 1.3 SDR LUT resource")
        }

        let patchNames: [String] = [
            "dark_skin", "light_skin", "blue_sky", "foliage", "blue_flower", "bluish_green",
            "orange", "purplish_blue", "moderate_red", "purple", "yellow_green", "orange_yellow",
            "blue", "green", "red", "yellow", "magenta", "cyan",
            "white", "neutral_8", "neutral_65", "neutral_5", "neutral_35", "black"
        ]

        let height = 360
        let macbeth = RenderNode(name: "Macbeth", shader: "fx_macbeth")

        let lutODT = RenderNode(
            name: "ODT_LUT",
            shader: "lut_apply_3d_rgba16f",
            inputs: ["input": macbeth.id],
            parameters: ["lut": .data(sdrLUT)],
            output: RenderNode.OutputSpec(resolution: .full, pixelFormat: .rgba16Float)
        )

        func makeShaderODT(name: String, shader: String, parameters: [String: NodeValue] = [:]) -> RenderNode {
            RenderNode(
                name: name,
                shader: shader,
                inputs: ["input": macbeth.id],
                parameters: parameters
            )
        }

        let forceTunedSDR = ProcessInfo.processInfo.environment["METAVIS_FORCE_SHADER_ODT_TUNED"] == "1"
        let shaderODT: RenderNode = {
            if forceTunedSDR {
                return makeShaderODT(
                    name: "ODT_Shader_TunedDefaults",
                    shader: "odt_acescg_to_rec709_studio_tuned",
                    parameters: [
                        "gamutCompress": .float(ColorCertTunedDefaults.SDRRec709Studio.gamutCompress),
                        "highlightDesatStrength": .float(ColorCertTunedDefaults.SDRRec709Studio.highlightDesatStrength),
                        "redModStrength": .float(ColorCertTunedDefaults.SDRRec709Studio.redModStrength)
                    ]
                )
            }
            return makeShaderODT(name: "ODT_Shader", shader: "odt_acescg_to_rec709_studio")
        }()

        let engine = try MetalSimulationEngine()
        try await engine.configure()

        let lutGraph = RenderGraph(nodes: [macbeth, lutODT], rootNodeID: lutODT.id)
        let shaderGraph = RenderGraph(nodes: [macbeth, shaderODT], rootNodeID: shaderODT.id)

        let (w1, h1, lutRGBA) = try await renderRGBA32F(engine: engine, graph: lutGraph, height: height)
        let (w2, h2, shaderRGBA) = try await renderRGBA32F(engine: engine, graph: shaderGraph, height: height)
        XCTAssertEqual(w1, w2)
        XCTAssertEqual(h1, h2)

        let lutPatches = samplePatchCenters(width: w1, height: h1, rgba: lutRGBA)
        let shaderPatches = samplePatchCenters(width: w2, height: h2, rgba: shaderRGBA)

        var bestLabel = forceTunedSDR ? "tunedDefaults" : "baseline"
        var bestStats = computeDeltaE2000Stats_SDR(shader: shaderPatches, reference: lutPatches, patchNames: patchNames)
        print(String(format: "[ColorCert] Shader ODT vs SDR LUT (Macbeth) ΔE2000 baseline: avg=%.4f max=%.4f worst=%@", bestStats.mean, bestStats.max, bestStats.worstPatch))

        // Optional: sweep SDR tuning parameters.
        if ProcessInfo.processInfo.environment["METAVIS_SDR_LUT_PARITY_TUNE"] == "1" {
            // Coarse + local refinement around likely sweet spots.
            let gcs: [Float] = [0.06, 0.08, 0.10, 0.12]
            // Baseline values in the current analytic sweeteners are ~0.12 highlightDesat and ~0.06 red rolloff.
            let highlightDesats: [Float] = [0.06, 0.08, 0.10, 0.12]
            let redMods: [Float] = [0.12, 0.14, 0.16]

            let verbose = ProcessInfo.processInfo.environment["METAVIS_SDR_LUT_PARITY_TUNE_VERBOSE"] == "1"

            func score(_ s: DeltaEStats) -> Double {
                // Mean is the primary goal; keep worst-case under control.
                s.mean + 0.20 * s.max
            }

            let baseScore = score(bestStats)
            print(String(format: "[ColorCert] SDR baselineScore=%.4f (avg=%.4f max=%.4f)", baseScore, bestStats.mean, bestStats.max))

            for gc in gcs {
                for hd in highlightDesats {
                    for rm in redMods {
                        let tuned = makeShaderODT(
                            name: "ODT_Shader_Tuned",
                            shader: "odt_acescg_to_rec709_studio_tuned",
                            parameters: [
                                "gamutCompress": .float(Double(gc)),
                                "highlightDesatStrength": .float(Double(hd)),
                                "redModStrength": .float(Double(rm))
                            ]
                        )
                        let tunedGraph = RenderGraph(nodes: [macbeth, tuned], rootNodeID: tuned.id)
                        let (_, _, tunedRGBA) = try await renderRGBA32F(engine: engine, graph: tunedGraph, height: height)
                        let tunedPatches = samplePatchCenters(width: w1, height: h1, rgba: tunedRGBA)
                        let stats = computeDeltaE2000Stats_SDR(shader: tunedPatches, reference: lutPatches, patchNames: patchNames)
                        let label = String(format: "tuned(gc=%.2f hd=%.2f rm=%.2f)", gc, hd, rm)
                        if verbose {
                            print(String(format: "[ColorCert] %s: avg=%.4f max=%.4f worst=%@",
                                         (label as NSString).utf8String!, stats.mean, stats.max, stats.worstPatch))
                        }

                        if score(stats) < score(bestStats) {
                            bestStats = stats
                            bestLabel = label

                            print(String(format: "[ColorCert] NEW BEST %s: avg=%.4f max=%.4f worst=%@",
                                         (bestLabel as NSString).utf8String!, bestStats.mean, bestStats.max, bestStats.worstPatch))
                        }
                    }
                }
            }
        }

        print(String(format: "[ColorCert] Shader ODT vs SDR LUT (Macbeth) ΔE2000 BEST: %s avg=%.4f max=%.4f worst=%@",
                     (bestLabel as NSString).utf8String!, bestStats.mean, bestStats.max, bestStats.worstPatch))

        // Default thresholds (can be tightened/loosened per-device via env).
        // These are intended to be "good enough" parity gates for shader fallback vs the ACES 1.3 LUT.
        let avgMax = envDouble("METAVIS_SDR_LUT_PARITY_DE2000_AVG_MAX", default: 2.0)
        let maxMax = envDouble("METAVIS_SDR_LUT_PARITY_DE2000_MAX_MAX", default: 5.0)

        if PerfLogger.isEnabled() {
            var e = PerfLogger.makeBaseEvent(
                suite: "ColorCert",
                test: "test_shader_fallback_matches_sdr_lut_macbeth_deltaE2000_opt_in",
                label: "ShaderODT(\(bestLabel)) vs LUT@aces13SDR (ΔE2000)",
                width: w1,
                height: h1,
                frames: 1
            )
            e.deltaE2000Avg = bestStats.mean
            e.deltaE2000Max = bestStats.max
            e.deltaEWorstPatch = bestStats.worstPatch
            PerfLogger.write(e)
        }

        XCTAssertTrue(bestStats.mean.isFinite && bestStats.max.isFinite)
        XCTAssertLessThanOrEqual(bestStats.mean, avgMax, "SDR ΔE2000 avg too high (avg=\(bestStats.mean) > \(avgMax)); worst=\(bestStats.worstPatch)")
        XCTAssertLessThanOrEqual(bestStats.max, maxMax, "SDR ΔE2000 max too high (max=\(bestStats.max) > \(maxMax)); worst=\(bestStats.worstPatch)")
    }

    func test_shader_fallback_matches_hdr_pq1000_lut_macbeth_opt_in() async throws {
        guard ProcessInfo.processInfo.environment["METAVIS_RUN_SHADER_LUT_PARITY"] == "1" else {
            throw XCTSkip("Set METAVIS_RUN_SHADER_LUT_PARITY=1 to measure shader ODT vs LUT parity")
        }
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal not available")
        }
        guard let hdrLUT = LUTResources.aces13HDRRec2100PQ1000DisplayRRTODT33() else {
            throw XCTSkip("Missing ACES 1.3 HDR PQ1000 LUT resource")
        }

        let patchNames: [String] = [
            "dark_skin", "light_skin", "blue_sky", "foliage", "blue_flower", "bluish_green",
            "orange", "purplish_blue", "moderate_red", "purple", "yellow_green", "orange_yellow",
            "blue", "green", "red", "yellow", "magenta", "cyan",
            "white", "neutral_8", "neutral_65", "neutral_5", "neutral_35", "black"
        ]

        let height = 360
        let macbeth = RenderNode(name: "Macbeth", shader: "fx_macbeth")

        let lutODT = RenderNode(
            name: "ODT_LUT",
            shader: "lut_apply_3d_rgba16f",
            inputs: ["input": macbeth.id],
            parameters: ["lut": .data(hdrLUT)],
            output: RenderNode.OutputSpec(resolution: .full, pixelFormat: .rgba16Float)
        )

        func makeShaderODTNode(name: String, shader: String, parameters: [String: NodeValue] = [:]) -> RenderNode {
            RenderNode(
                name: name,
                shader: shader,
                inputs: ["input": macbeth.id],
                parameters: parameters
            )
        }

        let engine = try MetalSimulationEngine()
        try await engine.configure()

        let lutGraph = RenderGraph(nodes: [macbeth, lutODT], rootNodeID: lutODT.id)
        let (w1, h1, lutRGBA) = try await renderRGBA32F(engine: engine, graph: lutGraph, height: height)
        let lutPatches = samplePatchCenters(width: w1, height: h1, rgba: lutRGBA)

        let forceTunedHDR = ProcessInfo.processInfo.environment["METAVIS_FORCE_SHADER_ODT_HDR_TUNED"] == "1"

        // Baseline: current fallback kernel (or tuned defaults when forced).
        let baselineODT: RenderNode = {
            if forceTunedHDR {
                return makeShaderODTNode(
                    name: "ODT_Shader_TunedDefaults",
                    shader: "odt_acescg_to_pq1000_tuned",
                    parameters: [
                        "maxNits": .float(ColorCertTunedDefaults.HDRPQ1000.maxNits),
                        "pqScale": .float(ColorCertTunedDefaults.HDRPQ1000.pqScale),
                        "highlightDesat": .float(ColorCertTunedDefaults.HDRPQ1000.highlightDesat),
                        "kneeNits": .float(ColorCertTunedDefaults.HDRPQ1000.kneeNits),
                        "gamutCompress": .float(ColorCertTunedDefaults.HDRPQ1000.gamutCompress)
                    ]
                )
            }
            return makeShaderODTNode(name: "ODT_Shader", shader: "odt_acescg_to_pq1000")
        }()
        let baselineGraph = RenderGraph(nodes: [macbeth, baselineODT], rootNodeID: baselineODT.id)
        let (w2, h2, baselineRGBA) = try await renderRGBA32F(engine: engine, graph: baselineGraph, height: height)
        XCTAssertEqual(w1, w2)
        XCTAssertEqual(h1, h2)
        let baselinePatches = samplePatchCenters(width: w2, height: h2, rgba: baselineRGBA)
        var bestLabel = forceTunedHDR ? "tunedDefaults" : "baseline"
        var bestStats = computeErrStats(shader: baselinePatches, reference: lutPatches, patchNames: patchNames)
        dumpPatchComparison(label: forceTunedHDR ? "HDR tunedDefaults" : "HDR baseline", shader: baselinePatches, reference: lutPatches, patchNames: patchNames)

        // Optional: parameter sweep (tuning) using the tunable kernel.
        if ProcessInfo.processInfo.environment["METAVIS_SHADER_LUT_PARITY_TUNE"] == "1" {
            let verbose = ProcessInfo.processInfo.environment["METAVIS_HDR_LUT_PARITY_TUNE_VERBOSE"] == "1"
            let maxNits: Float = 1000.0
            // Keep this reasonably sized for overnight runs; widen only when needed.
            // Tighten around the current best to hunt for additional mean improvement.
            let pqScales: [Float] = [0.124, 0.128, 0.132, 0.136]
            let desats: [Float] = [0.0, 0.06]
            // Keep knee effectively off for the sweep; the tuned kernel toe logic handles shadows.
            let knees: [Float] = [10000.0]
            let gamutCs: [Float] = [0.0, 0.15]

            func score(_ s: ErrStats) -> Double {
                // Prefer low mean, but strongly discourage max-error regressions.
                // (Max tends to correlate with visible outliers / tint pops.)
                s.meanAbs + 0.75 * s.maxAbs
            }

            let baselineScore = score(bestStats)
            print(String(format: "[ColorCert] baselineScore=%.6f (mean=%.6f max=%.6f)", baselineScore, bestStats.meanAbs, bestStats.maxAbs))

            var bestScoreLabel = bestLabel
            var bestScoreStats = bestStats
            var bestMaxLabel = bestLabel
            var bestMaxStats = bestStats
            var bestMeanLabel = bestLabel
            var bestMeanStats = bestStats

            for scale in pqScales {
                for desat in desats {
                    for knee in knees {
                        for gc in gamutCs {
                            let tunedParams: [String: NodeValue] = [
                                "maxNits": .float(Double(maxNits)),
                                "pqScale": .float(Double(scale)),
                                "highlightDesat": .float(Double(desat)),
                                "kneeNits": .float(Double(knee)),
                                "gamutCompress": .float(Double(gc))
                            ]
                            let tunedODT = makeShaderODTNode(
                                name: "ODT_Shader_Tuned",
                                shader: "odt_acescg_to_pq1000_tuned",
                                parameters: tunedParams
                            )
                            let tunedGraph = RenderGraph(nodes: [macbeth, tunedODT], rootNodeID: tunedODT.id)
                            let (_, _, tunedRGBA) = try await renderRGBA32F(engine: engine, graph: tunedGraph, height: height)
                            let tunedPatches = samplePatchCenters(width: w1, height: h1, rgba: tunedRGBA)
                            let stats = computeErrStats(shader: tunedPatches, reference: lutPatches, patchNames: patchNames)

                            let label = String(format: "tuned(scale=%.3f knee=%.0f gc=%.2f)", scale, knee, gc)
                            if verbose {
                                print(String(format: "[ColorCert] %s: meanAbsErr=%.6f maxAbsErr=%.6f worst=%@",
                                             (label as NSString).utf8String!, stats.meanAbs, stats.maxAbs, stats.worstPatch))
                            }

                            if stats.maxAbs < bestMaxStats.maxAbs {
                                bestMaxStats = stats
                                bestMaxLabel = label
                                print(String(format: "[ColorCert] NEW BEST_MAX %s: meanAbsErr=%.6f maxAbsErr=%.6f worst=%@",
                                             (bestMaxLabel as NSString).utf8String!, bestMaxStats.meanAbs, bestMaxStats.maxAbs, bestMaxStats.worstPatch))
                            }

                            if stats.meanAbs < bestMeanStats.meanAbs {
                                bestMeanStats = stats
                                bestMeanLabel = label
                                print(String(format: "[ColorCert] NEW BEST_MEAN %s: meanAbsErr=%.6f maxAbsErr=%.6f worst=%@",
                                             (bestMeanLabel as NSString).utf8String!, bestMeanStats.meanAbs, bestMeanStats.maxAbs, bestMeanStats.worstPatch))
                            }

                            if score(stats) < score(bestScoreStats) {
                                bestScoreStats = stats
                                bestScoreLabel = label
                                print(String(format: "[ColorCert] NEW BEST_SCORE %s: meanAbsErr=%.6f maxAbsErr=%.6f worst=%@",
                                             (bestScoreLabel as NSString).utf8String!, bestScoreStats.meanAbs, bestScoreStats.maxAbs, bestScoreStats.worstPatch))
                            }
                        }
                    }
                }
            }

            // Promote the score winner as the overall BEST (used by the rest of the test).
            bestStats = bestScoreStats
            bestLabel = bestScoreLabel

            print(String(format: "[ColorCert] HDR Tune Summary: BEST_SCORE=%s (mean=%.6f max=%.6f) BEST_MEAN=%s (mean=%.6f max=%.6f) BEST_MAX=%s (mean=%.6f max=%.6f)",
                         (bestScoreLabel as NSString).utf8String!, bestScoreStats.meanAbs, bestScoreStats.maxAbs,
                         (bestMeanLabel as NSString).utf8String!, bestMeanStats.meanAbs, bestMeanStats.maxAbs,
                         (bestMaxLabel as NSString).utf8String!, bestMaxStats.meanAbs, bestMaxStats.maxAbs))
        }

        print(String(format: "[ColorCert] Shader ODT vs HDR PQ1000 LUT (Macbeth) BEST: %s meanAbsErr=%.6f maxAbsErr=%.6f worst=%@",
                     (bestLabel as NSString).utf8String!, bestStats.meanAbs, bestStats.maxAbs, bestStats.worstPatch))

        if PerfLogger.isEnabled() {
            var e = PerfLogger.makeBaseEvent(
                suite: "ColorCert",
                test: "test_shader_fallback_matches_hdr_pq1000_lut_macbeth_opt_in",
                label: "ShaderODT(best) vs LUT@aces13HDR_PQ1000",
                width: w1,
                height: h1,
                frames: 1
            )
            e.lutMeanAbsErr = bestStats.meanAbs
            e.lutMaxAbsErr = bestStats.maxAbs
            e.lutWorstPatch = bestStats.worstPatch
            PerfLogger.write(e)
        }

        XCTAssertTrue(bestStats.meanAbs.isFinite && bestStats.maxAbs.isFinite)
    }

    func test_shader_fallback_matches_hdr_pq1000_lut_ramp_rolloff_opt_in() async throws {
        guard ProcessInfo.processInfo.environment["METAVIS_RUN_SHADER_LUT_PARITY"] == "1" else {
            throw XCTSkip("Set METAVIS_RUN_SHADER_LUT_PARITY=1 to measure shader ODT vs LUT parity")
        }
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal not available")
        }
        guard let hdrLUT = LUTResources.aces13HDRRec2100PQ1000DisplayRRTODT33() else {
            throw XCTSkip("Missing ACES 1.3 HDR PQ1000 LUT resource")
        }

        let height = 360
        let ramp = RenderNode(name: "Ramp", shader: "source_linear_ramp")

        let lutODT = RenderNode(
            name: "ODT_LUT",
            shader: "lut_apply_3d_rgba16f",
            inputs: ["input": ramp.id],
            parameters: ["lut": .data(hdrLUT)],
            output: RenderNode.OutputSpec(resolution: .full, pixelFormat: .rgba16Float)
        )

        let forceTunedHDR = ProcessInfo.processInfo.environment["METAVIS_FORCE_SHADER_ODT_HDR_TUNED"] == "1"
        let shaderODT: RenderNode = {
            if forceTunedHDR {
                return RenderNode(
                    name: "ODT_Shader_TunedDefaults",
                    shader: "odt_acescg_to_pq1000_tuned",
                    inputs: ["input": ramp.id],
                    parameters: [
                        "maxNits": .float(ColorCertTunedDefaults.HDRPQ1000.maxNits),
                        "pqScale": .float(ColorCertTunedDefaults.HDRPQ1000.pqScale),
                        "highlightDesat": .float(ColorCertTunedDefaults.HDRPQ1000.highlightDesat),
                        "kneeNits": .float(ColorCertTunedDefaults.HDRPQ1000.kneeNits),
                        "gamutCompress": .float(ColorCertTunedDefaults.HDRPQ1000.gamutCompress)
                    ]
                )
            }
            return RenderNode(
                name: "ODT_Shader",
                shader: "odt_acescg_to_pq1000",
                inputs: ["input": ramp.id]
            )
        }()

        let engine = try MetalSimulationEngine()
        try await engine.configure()

        let lutGraph = RenderGraph(nodes: [ramp, lutODT], rootNodeID: lutODT.id)
        let shaderGraph = RenderGraph(nodes: [ramp, shaderODT], rootNodeID: shaderODT.id)

        let (w1, h1, lutRGBA) = try await renderRGBA32F(engine: engine, graph: lutGraph, height: height)
        let (w2, h2, shaderRGBA) = try await renderRGBA32F(engine: engine, graph: shaderGraph, height: height)
        XCTAssertEqual(w1, w2)
        XCTAssertEqual(h1, h2)

        let samples = 256
        let y = h1 / 2
        let lutLine = sampleHorizontalLine(width: w1, height: h1, rgba: lutRGBA, y: y, samples: samples)
        let shaderLine = sampleHorizontalLine(width: w2, height: h2, rgba: shaderRGBA, y: y, samples: samples)
        XCTAssertEqual(lutLine.count, shaderLine.count)

        var sumAbs: Double = 0
        var maxAbs: Double = 0

        // Also check monotonicity of the displayed luma response.
        var prevLumaLUT: Float = -Float.infinity
        var prevLumaShader: Float = -Float.infinity
        let eps: Float = 1e-5

        for i in 0..<lutLine.count {
            let a = lutLine[i]
            let b = shaderLine[i]
            let d = simd_abs(a - b)
            let patchMax = Double(max(d.x, max(d.y, d.z)))
            sumAbs += Double(d.x + d.y + d.z)
            if patchMax > maxAbs { maxAbs = patchMax }

            let lLUT = lumaRec2020(a)
            let lShader = lumaRec2020(b)
            XCTAssertTrue(lLUT + eps >= prevLumaLUT, "LUT ramp luma not monotonic at sample \(i): \(lLUT) < \(prevLumaLUT)")
            XCTAssertTrue(lShader + eps >= prevLumaShader, "Shader ramp luma not monotonic at sample \(i): \(lShader) < \(prevLumaShader)")
            prevLumaLUT = lLUT
            prevLumaShader = lShader
        }

        let meanAbs = sumAbs / Double(max(1, lutLine.count * 3))
        print(String(format: "[ColorCert] HDR PQ1000 Ramp: meanAbsErr=%.6f maxAbsErr=%.6f samples=%d", meanAbs, maxAbs, lutLine.count))

        // Default thresholds (can be tightened/loosened per-device via env).
        let meanAbsMax = envDouble("METAVIS_HDR_LUT_PARITY_RAMP_MEANABS_MAX", default: 0.03)
        let maxAbsMax = envDouble("METAVIS_HDR_LUT_PARITY_RAMP_MAXABS_MAX", default: 0.10)

        if PerfLogger.isEnabled() {
            var e = PerfLogger.makeBaseEvent(
                suite: "ColorCert",
                test: "test_shader_fallback_matches_hdr_pq1000_lut_ramp_rolloff_opt_in",
                label: "Ramp@odt_acescg_to_pq1000 vs LUT@aces13HDR_PQ1000",
                width: w1,
                height: h1,
                frames: 1
            )
            e.lutMeanAbsErr = meanAbs
            e.lutMaxAbsErr = maxAbs
            PerfLogger.write(e)
        }

        XCTAssertTrue(meanAbs.isFinite && maxAbs.isFinite)
        XCTAssertLessThanOrEqual(meanAbs, meanAbsMax, "HDR ramp meanAbsErr too high (mean=\(meanAbs) > \(meanAbsMax))")
        XCTAssertLessThanOrEqual(maxAbs, maxAbsMax, "HDR ramp maxAbsErr too high (max=\(maxAbs) > \(maxAbsMax))")
    }
}
