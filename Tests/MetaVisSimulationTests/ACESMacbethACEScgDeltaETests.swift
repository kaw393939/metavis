import XCTest
import Metal
import simd
import MetaVisCore
@testable import MetaVisSimulation

final class ACESMacbethACEScgDeltaETests: XCTestCase {

    private struct LabD60: Equatable {
        var L: Double
        var a: Double
        var b: Double
    }

    // Macbeth patch values as used by the GPU generator (scene-linear ACEScg working space).
    // Must match `kMacbethColors` in Sources/MetaVisGraphics/Resources/Macbeth.metal.
    private let referenceACEScg: [(name: String, rgb: SIMD3<Double>)] = [
        ("dark_skin", SIMD3(0.092, 0.058, 0.042)),
        ("light_skin", SIMD3(0.360, 0.237, 0.187)),
        ("blue_sky", SIMD3(0.095, 0.132, 0.254)),
        ("foliage", SIMD3(0.080, 0.119, 0.043)),
        ("blue_flower", SIMD3(0.179, 0.164, 0.353)),
        ("bluish_green", SIMD3(0.102, 0.368, 0.301)),
        ("orange", SIMD3(0.547, 0.178, 0.032)),
        ("purplish_blue", SIMD3(0.055, 0.077, 0.245)),
        ("moderate_red", SIMD3(0.392, 0.081, 0.099)),
        ("purple", SIMD3(0.081, 0.037, 0.121)),
        ("yellow_green", SIMD3(0.360, 0.403, 0.043)),
        ("orange_yellow", SIMD3(0.624, 0.312, 0.017)),
        ("blue", SIMD3(0.023, 0.036, 0.208)),
        ("green", SIMD3(0.041, 0.231, 0.057)),
        ("red", SIMD3(0.310, 0.031, 0.033)),
        ("yellow", SIMD3(0.656, 0.527, 0.022)),
        ("magenta", SIMD3(0.372, 0.073, 0.228)),
        ("cyan", SIMD3(0.063, 0.271, 0.455)),
        ("white", SIMD3(0.889, 0.889, 0.889)),
        ("neutral_8", SIMD3(0.566, 0.566, 0.566)),
        ("neutral_65", SIMD3(0.351, 0.351, 0.351)),
        ("neutral_5", SIMD3(0.187, 0.187, 0.187)),
        ("neutral_35", SIMD3(0.085, 0.085, 0.085)),
        ("black", SIMD3(0.030, 0.030, 0.030))
    ]

    func test_macbeth_acescg_scene_referred_deltaE2000_opt_in() async throws {
        guard ProcessInfo.processInfo.environment["METAVIS_RUN_COLOR_CERT"] == "1" else {
            throw XCTSkip("Set METAVIS_RUN_COLOR_CERT=1 to compute/report Macbeth ACEScg ΔE")
        }

        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal not available")
        }

        // Render in linear ACEScg (no ODT) so we measure working-space correctness.
        let height = 360
        let width = height * 16 / 9

        let macbeth = RenderNode(name: "Macbeth", shader: "fx_macbeth")
        let graph = RenderGraph(nodes: [macbeth], rootNodeID: macbeth.id)

        let quality = QualityProfile(name: "MacbethACEScgDeltaE", fidelity: .high, resolutionHeight: height, colorDepth: 10)
        let request = RenderRequest(graph: graph, time: .zero, quality: quality)

        let engine = try MetalSimulationEngine()
        try await engine.configure()

        // Use RGBA16F pixel buffer path to avoid any float32 export encoding/decoding.
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

        try await engine.render(request: request, to: pb)

        // Sample the center of each patch cell (6x4), avoiding the border.
        func sampleACEScg(col: Int, row: Int) -> SIMD3<Double> {
            let u = (Double(col) + 0.5) / 6.0
            let v = (Double(row) + 0.5) / 4.0
            let x = min(max(Int(u * Double(width)), 0), width - 1)
            let y = min(max(Int(v * Double(height)), 0), height - 1)

            CVPixelBufferLockBaseAddress(pb, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
            guard let baseAddr = CVPixelBufferGetBaseAddress(pb) else { return SIMD3(0, 0, 0) }
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
            let strideU16 = bytesPerRow / MemoryLayout<UInt16>.size
            let base = baseAddr.assumingMemoryBound(to: UInt16.self)
            let rowPtr = base.advanced(by: y * strideU16)
            let px = rowPtr.advanced(by: x * 4)

            let r = Double(Float(Float16(bitPattern: px[0])))
            let g = Double(Float(Float16(bitPattern: px[1])))
            let b = Double(Float(Float16(bitPattern: px[2])))
            return SIMD3(r, g, b)
        }

        func acescgToLabD60(_ rgb: SIMD3<Double>) -> LabD60 {
            // ACEScg(AP1) -> XYZ (D60)
            // Matrix matches the one in the MetaVisLab notes (and ACEScg primaries).
            let X = 0.6624541811 * rgb.x + 0.2722287168 * rgb.y + (-0.0055746495) * rgb.z
            let Y = 0.1340042065 * rgb.x + 0.6740817658 * rgb.y + 0.0040607335 * rgb.z
            let Z = 0.1561876870 * rgb.x + 0.0536895174 * rgb.y + 1.0103391003 * rgb.z

            // D60 white point used in ACEScg Lab conversion.
            let Xn = 0.9526460746
            let Yn = 1.0
            let Zn = 1.0088251843

            let xn = X / Xn
            let yn = Y / Yn
            let zn = Z / Zn

            func f(_ t: Double) -> Double {
                let eps = 216.0 / 24389.0
                let kappa = 24389.0 / 27.0
                return t > eps ? pow(t, 1.0 / 3.0) : (kappa * t + 16.0) / 116.0
            }

            let fx = f(xn)
            let fy = f(yn)
            let fz = f(zn)

            return LabD60(
                L: 116.0 * fy - 16.0,
                a: 500.0 * (fx - fy),
                b: 200.0 * (fy - fz)
            )
        }

        func deltaE2000(_ lab1: LabD60, _ lab2: LabD60) -> Double {
            // Standard CIEDE2000 implementation.
            let kL = 1.0, kC = 1.0, kH = 1.0

            let L1 = lab1.L, a1 = lab1.a, b1 = lab1.b
            let L2 = lab2.L, a2 = lab2.a, b2 = lab2.b

            let C1 = sqrt(a1 * a1 + b1 * b1)
            let C2 = sqrt(a2 * a2 + b2 * b2)
            let C_bar = (C1 + C2) / 2.0

            let G = 0.5 * (1.0 - sqrt(pow(C_bar, 7) / (pow(C_bar, 7) + pow(25.0, 7))))

            let a1p = (1.0 + G) * a1
            let a2p = (1.0 + G) * a2

            let C1p = sqrt(a1p * a1p + b1 * b1)
            let C2p = sqrt(a2p * a2p + b2 * b2)

            func atan2deg(_ y: Double, _ x: Double) -> Double {
                let deg = atan2(y, x) * 180.0 / .pi
                return deg >= 0 ? deg : deg + 360.0
            }

            let h1 = (b1 == 0 && a1p == 0) ? 0.0 : atan2deg(b1, a1p)
            let h2 = (b2 == 0 && a2p == 0) ? 0.0 : atan2deg(b2, a2p)

            let dLp = L2 - L1
            let dCp = C2p - C1p

            var dhp = 0.0
            if (C1p * C2p) != 0 {
                if abs(h2 - h1) <= 180 {
                    dhp = h2 - h1
                } else if (h2 - h1) > 180 {
                    dhp = h2 - h1 - 360
                } else {
                    dhp = h2 - h1 + 360
                }
            }

            let dHp = 2.0 * sqrt(C1p * C2p) * sin((dhp / 2.0) * .pi / 180.0)

            let Lbp = (L1 + L2) / 2.0
            let Cbp = (C1p + C2p) / 2.0

            var hbp = 0.0
            if (C1p * C2p) != 0 {
                if abs(h1 - h2) <= 180 {
                    hbp = (h1 + h2) / 2.0
                } else if (h1 + h2) < 360 {
                    hbp = (h1 + h2 + 360) / 2.0
                } else {
                    hbp = (h1 + h2 - 360) / 2.0
                }
            } else {
                hbp = h1 + h2
            }

            let T = 1.0 - 0.17 * cos((hbp - 30.0) * .pi / 180.0)
                + 0.24 * cos((2.0 * hbp) * .pi / 180.0)
                + 0.32 * cos((3.0 * hbp + 6.0) * .pi / 180.0)
                - 0.20 * cos((4.0 * hbp - 63.0) * .pi / 180.0)

            let dTheta = 30.0 * exp(-pow((hbp - 275.0) / 25.0, 2))
            let RC = 2.0 * sqrt(pow(Cbp, 7) / (pow(Cbp, 7) + pow(25.0, 7)))
            let SL = 1.0 + (0.015 * pow(Lbp - 50.0, 2)) / sqrt(20.0 + pow(Lbp - 50.0, 2))
            let SC = 1.0 + 0.045 * Cbp
            let SH = 1.0 + 0.015 * Cbp * T
            let RT = -sin((2.0 * dTheta) * .pi / 180.0) * RC

            let t1 = dLp / (kL * SL)
            let t2 = dCp / (kC * SC)
            let t3 = dHp / (kH * SH)

            return sqrt(t1 * t1 + t2 * t2 + t3 * t3 + RT * t2 * t3)
        }

        var deltas: [(String, Double)] = []
        deltas.reserveCapacity(24)

        for row in 0..<4 {
            for col in 0..<6 {
                let idx = row * 6 + col
                let ref = referenceACEScg[idx]
                let measRGB = sampleACEScg(col: col, row: row)

                let refLab = acescgToLabD60(ref.rgb)
                let measLab = acescgToLabD60(measRGB)
                let de = deltaE2000(measLab, refLab)
                deltas.append((ref.name, de))
            }
        }

        let avg = deltas.map { $0.1 }.reduce(0.0, +) / Double(deltas.count)
        let maxV = deltas.map { $0.1 }.max() ?? 0.0
        let worst = deltas.max(by: { $0.1 < $1.1 })?.0 ?? "(unknown)"

        print(String(format: "[ColorCert] Macbeth ACEScg(scene) ΔE2000: avg=%.4f max=%.4f worst=%@", avg, maxV, worst))

        if PerfLogger.isEnabled() {
            var e = PerfLogger.makeBaseEvent(
                suite: "ColorCert",
                test: "test_macbeth_acescg_scene_referred_deltaE2000_opt_in",
                label: "Macbeth@acescg_scene",
                width: width,
                height: height,
                frames: 1
            )
            e.deltaE2000Avg = avg
            e.deltaE2000Max = maxV
            e.deltaEWorstPatch = worst
            PerfLogger.write(e)
        }

        XCTAssertTrue(avg.isFinite && maxV.isFinite)
    }
}
