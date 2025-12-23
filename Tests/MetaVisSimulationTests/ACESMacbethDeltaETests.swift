import XCTest
import Metal
import simd
import MetaVisCore
import MetaVisGraphics
@testable import MetaVisSimulation

final class ACESMacbethDeltaETests: XCTestCase {

    private struct Lab: Equatable {
        var L: Double
        var a: Double
        var b: Double
    }

    // Reference values (sRGB D65) for ISO 17321-1 ColorChecker Classic.
    // Sourced from the existing MetaVisLab draft CLI (kept here so tests are self-contained).
    private let referenceSRGB: [(name: String, rgb: SIMD3<Double>)] = [
        ("dark_skin", SIMD3(0.451, 0.313, 0.256)),
        ("light_skin", SIMD3(0.769, 0.596, 0.510)),
        ("blue_sky", SIMD3(0.373, 0.451, 0.639)),
        ("foliage", SIMD3(0.353, 0.412, 0.263)),
        ("blue_flower", SIMD3(0.518, 0.494, 0.694)),
        ("bluish_green", SIMD3(0.404, 0.725, 0.659)),
        ("orange", SIMD3(0.851, 0.478, 0.180)),
        ("purplish_blue", SIMD3(0.267, 0.349, 0.616)),
        ("moderate_red", SIMD3(0.765, 0.329, 0.365)),
        ("purple", SIMD3(0.365, 0.231, 0.412)),
        ("yellow_green", SIMD3(0.608, 0.733, 0.231)),
        ("orange_yellow", SIMD3(0.890, 0.651, 0.161)),
        ("blue", SIMD3(0.110, 0.208, 0.588)),
        ("green", SIMD3(0.271, 0.584, 0.275)),
        ("red", SIMD3(0.690, 0.192, 0.212)),
        ("yellow", SIMD3(0.929, 0.800, 0.180)),
        ("magenta", SIMD3(0.733, 0.329, 0.612)),
        ("cyan", SIMD3(0.000, 0.533, 0.655)),
        ("white", SIMD3(0.953, 0.953, 0.953)),
        ("neutral_8", SIMD3(0.784, 0.784, 0.784)),
        ("neutral_65", SIMD3(0.627, 0.627, 0.627)),
        ("neutral_5", SIMD3(0.478, 0.478, 0.478)),
        ("neutral_35", SIMD3(0.333, 0.333, 0.333)),
        ("black", SIMD3(0.118, 0.118, 0.118))
    ]

    func test_macbeth_deltaE2000_reports_current_value_opt_in() async throws {
        // Legacy / informational only:
        // This compares an ACES display rendering (RRT+ODT) result to ISO sRGB patch triplets.
        // That is NOT a valid reference-grade accuracy test (apples-to-oranges).
        // Keep it available for exploratory tracking, but opt-in separately.
        guard ProcessInfo.processInfo.environment["METAVIS_RUN_COLOR_CERT_LEGACY"] == "1" else {
            throw XCTSkip("Set METAVIS_RUN_COLOR_CERT_LEGACY=1 to run legacy display-referred ΔE test")
        }

        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal not available")
        }

        let height = 360
        let width = height * 16 / 9

        let macbeth = RenderNode(name: "Macbeth", shader: "fx_macbeth")
        let odt = RenderNode(name: "ODT", shader: "odt_acescg_to_rec709", inputs: ["input": macbeth.id])
        let graph = RenderGraph(nodes: [macbeth, odt], rootNodeID: odt.id)

        let quality = QualityProfile(name: "MacbethDeltaE", fidelity: .high, resolutionHeight: height, colorDepth: 32)
        let request = RenderRequest(graph: graph, time: .zero, quality: quality)

        let engine = try MetalSimulationEngine()
        try await engine.configure()

        let result = try await engine.render(request: request)
        guard let data = result.imageBuffer else {
            XCTFail("No imageBuffer produced: \(result.metadata)")
            return
        }

        let expectedFloats = width * height * 4
        let rgba: [Float] = data.withUnsafeBytes { raw in
            let base = raw.bindMemory(to: Float.self)
            return Array(base.prefix(expectedFloats))
        }
        XCTAssertEqual(rgba.count, expectedFloats)

        // Sample the center of each patch cell (6x4), avoiding the border.
        func sampleSRGB(col: Int, row: Int) -> SIMD3<Double> {
            let u = (Double(col) + 0.5) / 6.0
            let v = (Double(row) + 0.5) / 4.0
            let x = min(max(Int(u * Double(width)), 0), width - 1)
            let y = min(max(Int(v * Double(height)), 0), height - 1)
            let idx = (y * width + x) * 4
            let r = Double(rgba[idx + 0])
            let g = Double(rgba[idx + 1])
            let b = Double(rgba[idx + 2])
            // ODT clamps to [0,1], but keep defensive clamp here.
            return SIMD3(max(0.0, min(1.0, r)), max(0.0, min(1.0, g)), max(0.0, min(1.0, b)))
        }

        func srgbToLinear(_ v: Double) -> Double {
            if v <= 0.04045 { return v / 12.92 }
            return pow((v + 0.055) / 1.055, 2.4)
        }

        func rgbToLab_D65(_ srgb: SIMD3<Double>) -> Lab {
            // 1) sRGB -> linear RGB (Rec.709 primaries, D65)
            let r = srgbToLinear(srgb.x)
            let g = srgbToLinear(srgb.y)
            let b = srgbToLinear(srgb.z)

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

            return Lab(
                L: 116.0 * fy - 16.0,
                a: 500.0 * (fx - fy),
                b: 200.0 * (fy - fz)
            )
        }

        func deltaE2000(_ lab1: Lab, _ lab2: Lab) -> Double {
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

        var deltas: [(String, Double)] = []
        deltas.reserveCapacity(24)

        for row in 0..<4 {
            for col in 0..<6 {
                let idx = row * 6 + col
                let ref = referenceSRGB[idx]
                let meas = sampleSRGB(col: col, row: row)

                let refLab = rgbToLab_D65(ref.rgb)
                let measLab = rgbToLab_D65(meas)
                let de = deltaE2000(measLab, refLab)
                deltas.append((ref.name, de))
            }
        }

        let avg = deltas.map { $0.1 }.reduce(0.0, +) / Double(deltas.count)
        let maxV = deltas.map { $0.1 }.max() ?? 0.0
        let worst = deltas.max(by: { $0.1 < $1.1 })?.0 ?? "(unknown)"

        print(String(format: "[ColorCert] Macbeth ΔE2000: avg=%.3f max=%.3f worst=%@", avg, maxV, worst))

        if PerfLogger.isEnabled() {
            var e = PerfLogger.makeBaseEvent(
                suite: "ColorCert",
                test: "test_macbeth_deltaE2000_reports_current_value_opt_in",
                label: "Macbeth@odt_acescg_to_rec709",
                width: width,
                height: height,
                frames: 1
            )
            e.deltaE2000Avg = avg
            e.deltaE2000Max = maxV
            e.deltaEWorstPatch = worst
            PerfLogger.write(e)
        }

        // This test is currently informational by default (no threshold enforced).
        // Once ACES 1.3 ODT/validators land, we can lock thresholds.
        XCTAssertTrue(avg.isFinite && maxV.isFinite)
    }

    func test_macbeth_deltaE2000_reports_current_value_studio_odt_opt_in() async throws {
        guard ProcessInfo.processInfo.environment["METAVIS_RUN_COLOR_CERT"] == "1" else {
            throw XCTSkip("Set METAVIS_RUN_COLOR_CERT=1 to compute/report Macbeth ΔE")
        }

        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal not available")
        }

        // NOTE:
        // The Studio path applies an ACES RRT+ODT “display rendering” transform.
        // Comparing that output to ISO sRGB ColorChecker reference triplets is not a valid “reference” ΔE test.
        // Instead, validate that our GPU LUT application matches a CPU evaluation of the same baked LUT.

        let height = 360
        let width = height * 16 / 9

        guard let lutData = LUTResources.aces13SDRSRGBDisplayRRTODT33() else {
            XCTFail("Missing baked ACES 1.3 LUT resource")
            return
        }
        guard let (lutSize, lutPayloadRGB) = LUTHelper.parseCube(data: lutData) else {
            XCTFail("Failed to parse baked ACES 1.3 LUT")
            return
        }

        let macbeth = RenderNode(name: "Macbeth", shader: "fx_macbeth")
        let odt = RenderNode(
            name: "ODT",
            shader: "lut_apply_3d_rgba16f",
            inputs: ["input": macbeth.id],
            parameters: ["lut": .data(lutData)],
            output: RenderNode.OutputSpec(resolution: .full, pixelFormat: .rgba16Float)
        )

        let graphInput = RenderGraph(nodes: [macbeth], rootNodeID: macbeth.id)
        let graphOutput = RenderGraph(nodes: [macbeth, odt], rootNodeID: odt.id)

        let quality = QualityProfile(name: "MacbethStudioLUTReference", fidelity: .high, resolutionHeight: height, colorDepth: 32)
        let requestInput = RenderRequest(graph: graphInput, time: .zero, quality: quality)
        let requestOutput = RenderRequest(graph: graphOutput, time: .zero, quality: quality)

        let engine = try MetalSimulationEngine()
        try await engine.configure()

        let inputResult = try await engine.render(request: requestInput)
        guard let inputData = inputResult.imageBuffer else {
            XCTFail("No input imageBuffer produced: \(inputResult.metadata)")
            return
        }

        let outputResult = try await engine.render(request: requestOutput)
        guard let outputData = outputResult.imageBuffer else {
            XCTFail("No output imageBuffer produced: \(outputResult.metadata)")
            return
        }

        let expectedFloats = width * height * 4
        let inputRGBA: [Float] = inputData.withUnsafeBytes { raw in
            let base = raw.bindMemory(to: Float.self)
            return Array(base.prefix(expectedFloats))
        }
        let outputRGBA: [Float] = outputData.withUnsafeBytes { raw in
            let base = raw.bindMemory(to: Float.self)
            return Array(base.prefix(expectedFloats))
        }
        XCTAssertEqual(inputRGBA.count, expectedFloats)
        XCTAssertEqual(outputRGBA.count, expectedFloats)

        func sampleRGB(_ rgba: [Float], col: Int, row: Int) -> SIMD3<Float> {
            let u = (Float(col) + 0.5) / 6.0
            let v = (Float(row) + 0.5) / 4.0
            let x = min(max(Int(Double(u) * Double(width)), 0), width - 1)
            let y = min(max(Int(Double(v) * Double(height)), 0), height - 1)
            let idx = (y * width + x) * 4
            return SIMD3(rgba[idx + 0], rgba[idx + 1], rgba[idx + 2])
        }

        func lutEntryRGB(r: Int, g: Int, b: Int) -> SIMD3<Float> {
            let idx = (r + g * lutSize + b * lutSize * lutSize) * 3
            return SIMD3(lutPayloadRGB[idx + 0], lutPayloadRGB[idx + 1], lutPayloadRGB[idx + 2])
        }

        func clamp01(_ x: Float) -> Float { min(max(x, 0.0), 1.0) }

        // Approximate Metal normalized sampling for 3D textures with linear filter:
        // scaled = coord * size - 0.5; indices = floor(scaled), lerp via frac(scaled)
        func applyCubeLUT_CPU(_ rgb: SIMD3<Float>) -> SIMD3<Float> {
            let r = clamp01(rgb.x)
            let g = clamp01(rgb.y)
            let b = clamp01(rgb.z)

            func axis(_ v: Float) -> (i0: Int, i1: Int, t: Float) {
                let scaled = v * Float(lutSize) - 0.5
                var i0 = Int(floor(Double(scaled)))
                var t = scaled - Float(i0)
                if i0 < 0 { i0 = 0; t = 0 }
                if i0 >= lutSize - 1 { i0 = lutSize - 1; t = 0 }
                let i1 = min(i0 + 1, lutSize - 1)
                return (i0, i1, min(max(t, 0.0), 1.0))
            }

            let ar = axis(r)
            let ag = axis(g)
            let ab = axis(b)

            func lerp(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> { a * (1 - t) + b * t }

            let c000 = lutEntryRGB(r: ar.i0, g: ag.i0, b: ab.i0)
            let c100 = lutEntryRGB(r: ar.i1, g: ag.i0, b: ab.i0)
            let c010 = lutEntryRGB(r: ar.i0, g: ag.i1, b: ab.i0)
            let c110 = lutEntryRGB(r: ar.i1, g: ag.i1, b: ab.i0)
            let c001 = lutEntryRGB(r: ar.i0, g: ag.i0, b: ab.i1)
            let c101 = lutEntryRGB(r: ar.i1, g: ag.i0, b: ab.i1)
            let c011 = lutEntryRGB(r: ar.i0, g: ag.i1, b: ab.i1)
            let c111 = lutEntryRGB(r: ar.i1, g: ag.i1, b: ab.i1)

            let c00 = lerp(c000, c100, ar.t)
            let c10 = lerp(c010, c110, ar.t)
            let c01 = lerp(c001, c101, ar.t)
            let c11 = lerp(c011, c111, ar.t)

            let c0 = lerp(c00, c10, ag.t)
            let c1 = lerp(c01, c11, ag.t)

            return lerp(c0, c1, ab.t)
        }

        var maxAbsError: Float = 0
        var sumAbsError: Float = 0
        var count: Int = 0
        var worstPatch: String = "(unknown)"

        for row in 0..<4 {
            for col in 0..<6 {
                let idx = row * 6 + col
                let patchName = referenceSRGB[idx].name
                let acescg = sampleRGB(inputRGBA, col: col, row: row)
                let gpu = sampleRGB(outputRGBA, col: col, row: row)
                let cpu = applyCubeLUT_CPU(acescg)

                let err = simd_abs(gpu - cpu)
                maxAbsError = max(maxAbsError, max(err.x, max(err.y, err.z)))
                sumAbsError += (err.x + err.y + err.z)
                count += 3

                if max(err.x, max(err.y, err.z)) == maxAbsError {
                    worstPatch = patchName
                }

                XCTAssertTrue(gpu.x.isFinite && gpu.y.isFinite && gpu.z.isFinite)
            }
        }

        let meanAbsError = (count > 0) ? (sumAbsError / Float(count)) : 0
        print(String(format: "[ColorCert] Studio LUT reference match: meanAbsErr=%.6f maxAbsErr=%.6f worst=%@", meanAbsError, maxAbsError, worstPatch))

        if PerfLogger.isEnabled() {
            var e = PerfLogger.makeBaseEvent(
                suite: "ColorCert",
                test: "test_macbeth_studio_lut_reference_match_opt_in",
                label: "StudioLUTMatch",
                width: width,
                height: height,
                frames: 1
            )
            e.lutMeanAbsErr = Double(meanAbsError)
            e.lutMaxAbsErr = Double(maxAbsError)
            e.lutWorstPatch = worstPatch
            PerfLogger.write(e)
        }

        // Tolerance: allow small differences due to GPU sampler precision and coordinate conventions.
        XCTAssertLessThanOrEqual(maxAbsError, 0.02)
    }

    func test_macbeth_hdr_pq1000_lut_reference_match_opt_in() async throws {
        guard ProcessInfo.processInfo.environment["METAVIS_RUN_COLOR_REFERENCE_MATCH"] == "1" else {
            throw XCTSkip("Set METAVIS_RUN_COLOR_REFERENCE_MATCH=1 to validate HDR LUT GPU-vs-CPU match")
        }

        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal not available")
        }

        let height = 180
        let width = height * 16 / 9

        guard let lutData = LUTResources.aces13HDRRec2100PQ1000DisplayRRTODT33() else {
            XCTFail("Missing baked ACES 1.3 HDR PQ1000 LUT resource")
            return
        }
        guard let (lutSize, lutPayloadRGB) = LUTHelper.parseCube(data: lutData) else {
            XCTFail("Failed to parse baked ACES 1.3 HDR PQ1000 LUT")
            return
        }

        let macbeth = RenderNode(name: "Macbeth", shader: "fx_macbeth")
        let odt = RenderNode(
            name: "ODT",
            shader: "lut_apply_3d_rgba16f",
            inputs: ["input": macbeth.id],
            parameters: ["lut": .data(lutData)],
            output: RenderNode.OutputSpec(resolution: .full, pixelFormat: .rgba16Float)
        )

        let graphInput = RenderGraph(nodes: [macbeth], rootNodeID: macbeth.id)
        let graphOutput = RenderGraph(nodes: [macbeth, odt], rootNodeID: odt.id)

        let quality = QualityProfile(name: "MacbethHDRLUTReference", fidelity: .high, resolutionHeight: height, colorDepth: 32)
        let requestInput = RenderRequest(graph: graphInput, time: .zero, quality: quality)
        let requestOutput = RenderRequest(graph: graphOutput, time: .zero, quality: quality)

        let engine = try MetalSimulationEngine()
        try await engine.configure()

        let inputResult = try await engine.render(request: requestInput)
        guard let inputData = inputResult.imageBuffer else {
            XCTFail("No input imageBuffer produced: \(inputResult.metadata)")
            return
        }

        let outputResult = try await engine.render(request: requestOutput)
        guard let outputData = outputResult.imageBuffer else {
            XCTFail("No output imageBuffer produced: \(outputResult.metadata)")
            return
        }

        let expectedFloats = width * height * 4
        let inputRGBA: [Float] = inputData.withUnsafeBytes { raw in
            let base = raw.bindMemory(to: Float.self)
            return Array(base.prefix(expectedFloats))
        }
        let outputRGBA: [Float] = outputData.withUnsafeBytes { raw in
            let base = raw.bindMemory(to: Float.self)
            return Array(base.prefix(expectedFloats))
        }
        XCTAssertEqual(inputRGBA.count, expectedFloats)
        XCTAssertEqual(outputRGBA.count, expectedFloats)

        func sampleRGB(_ rgba: [Float], col: Int, row: Int) -> SIMD3<Float> {
            let u = (Float(col) + 0.5) / 6.0
            let v = (Float(row) + 0.5) / 4.0
            let x = min(max(Int(Double(u) * Double(width)), 0), width - 1)
            let y = min(max(Int(Double(v) * Double(height)), 0), height - 1)
            let idx = (y * width + x) * 4
            return SIMD3(rgba[idx + 0], rgba[idx + 1], rgba[idx + 2])
        }

        func lutEntryRGB(r: Int, g: Int, b: Int) -> SIMD3<Float> {
            let idx = (r + g * lutSize + b * lutSize * lutSize) * 3
            return SIMD3(lutPayloadRGB[idx + 0], lutPayloadRGB[idx + 1], lutPayloadRGB[idx + 2])
        }

        func clamp01(_ x: Float) -> Float { min(max(x, 0.0), 1.0) }

        func applyCubeLUT_CPU(_ rgb: SIMD3<Float>) -> SIMD3<Float> {
            let r = clamp01(rgb.x)
            let g = clamp01(rgb.y)
            let b = clamp01(rgb.z)

            func axis(_ v: Float) -> (i0: Int, i1: Int, t: Float) {
                let scaled = v * Float(lutSize) - 0.5
                var i0 = Int(floor(Double(scaled)))
                var t = scaled - Float(i0)
                if i0 < 0 { i0 = 0; t = 0 }
                if i0 >= lutSize - 1 { i0 = lutSize - 1; t = 0 }
                let i1 = min(i0 + 1, lutSize - 1)
                return (i0, i1, min(max(t, 0.0), 1.0))
            }

            let ar = axis(r)
            let ag = axis(g)
            let ab = axis(b)

            func lerp(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> { a * (1 - t) + b * t }

            let c000 = lutEntryRGB(r: ar.i0, g: ag.i0, b: ab.i0)
            let c100 = lutEntryRGB(r: ar.i1, g: ag.i0, b: ab.i0)
            let c010 = lutEntryRGB(r: ar.i0, g: ag.i1, b: ab.i0)
            let c110 = lutEntryRGB(r: ar.i1, g: ag.i1, b: ab.i0)
            let c001 = lutEntryRGB(r: ar.i0, g: ag.i0, b: ab.i1)
            let c101 = lutEntryRGB(r: ar.i1, g: ag.i0, b: ab.i1)
            let c011 = lutEntryRGB(r: ar.i0, g: ag.i1, b: ab.i1)
            let c111 = lutEntryRGB(r: ar.i1, g: ag.i1, b: ab.i1)

            let c00 = lerp(c000, c100, ar.t)
            let c10 = lerp(c010, c110, ar.t)
            let c01 = lerp(c001, c101, ar.t)
            let c11 = lerp(c011, c111, ar.t)

            let c0 = lerp(c00, c10, ag.t)
            let c1 = lerp(c01, c11, ag.t)

            return lerp(c0, c1, ab.t)
        }

        var maxAbsError: Float = 0
        var sumAbsError: Float = 0
        var count: Int = 0
        var worstPatch: String = "(unknown)"

        // Use the 6x4 Macbeth grid as a stable, deterministic set of probe colors.
        for row in 0..<4 {
            for col in 0..<6 {
                let idx = row * 6 + col
                let patchName = referenceSRGB[idx].name
                let acescg = sampleRGB(inputRGBA, col: col, row: row)
                let gpu = sampleRGB(outputRGBA, col: col, row: row)
                let cpu = applyCubeLUT_CPU(acescg)

                let err = simd_abs(gpu - cpu)
                maxAbsError = max(maxAbsError, max(err.x, max(err.y, err.z)))
                sumAbsError += (err.x + err.y + err.z)
                count += 3

                if max(err.x, max(err.y, err.z)) == maxAbsError {
                    worstPatch = patchName
                }

                XCTAssertTrue(gpu.x.isFinite && gpu.y.isFinite && gpu.z.isFinite)
            }
        }

        let meanAbsError = (count > 0) ? (sumAbsError / Float(count)) : 0
        print(String(format: "[ColorCert] HDR PQ1000 LUT reference match: meanAbsErr=%.6f maxAbsErr=%.6f worst=%@", meanAbsError, maxAbsError, worstPatch))

        if PerfLogger.isEnabled() {
            var e = PerfLogger.makeBaseEvent(
                suite: "ColorCert",
                test: "test_macbeth_hdr_pq1000_lut_reference_match_opt_in",
                label: "HDRPQLUTMatch",
                width: width,
                height: height,
                frames: 1
            )
            e.lutMeanAbsErr = Double(meanAbsError)
            e.lutMaxAbsErr = Double(maxAbsError)
            e.lutWorstPatch = worstPatch
            PerfLogger.write(e)
        }

        XCTAssertLessThanOrEqual(maxAbsError, 0.02)
    }

    func test_macbeth_hdr_pq1000_lut_smoke_opt_in() async throws {
        guard ProcessInfo.processInfo.environment["METAVIS_RUN_COLOR_CERT"] == "1" else {
            throw XCTSkip("Set METAVIS_RUN_COLOR_CERT=1 to run HDR LUT smoke test")
        }

        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal not available")
        }

        let height = 180
        let width = height * 16 / 9

        guard let lut = LUTResources.aces13HDRRec2100PQ1000DisplayRRTODT33() else {
            XCTFail("Missing baked ACES 1.3 HDR PQ1000 LUT resource")
            return
        }

        let macbeth = RenderNode(name: "Macbeth", shader: "fx_macbeth")
        let odt = RenderNode(
            name: "ODT",
            shader: "lut_apply_3d",
            inputs: ["input": macbeth.id],
            parameters: ["lut": .data(lut)]
        )
        let graph = RenderGraph(nodes: [macbeth, odt], rootNodeID: odt.id)

        let quality = QualityProfile(name: "MacbethHDRLUTSmoke", fidelity: .high, resolutionHeight: height, colorDepth: 32)
        let request = RenderRequest(graph: graph, time: .zero, quality: quality)

        let engine = try MetalSimulationEngine()
        try await engine.configure()

        let result = try await engine.render(request: request)
        guard let data = result.imageBuffer else {
            XCTFail("No imageBuffer produced: \(result.metadata)")
            return
        }

        let expectedFloats = width * height * 4
        let rgba: [Float] = data.withUnsafeBytes { raw in
            let base = raw.bindMemory(to: Float.self)
            return Array(base.prefix(expectedFloats))
        }
        XCTAssertEqual(rgba.count, expectedFloats)

        var minV: Float = .greatestFiniteMagnitude
        var maxV: Float = -.greatestFiniteMagnitude
        for v in rgba {
            XCTAssertTrue(v.isFinite)
            minV = min(minV, v)
            maxV = max(maxV, v)
        }

        // PQ-encoded display output should be in a sane [0,1] range (allow tiny numerical slop).
        XCTAssertGreaterThanOrEqual(minV, -0.01)
        XCTAssertLessThanOrEqual(maxV, 1.01)
    }
}
