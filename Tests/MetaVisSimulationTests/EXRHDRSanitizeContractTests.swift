import XCTest
import Foundation
import Metal
import MetaVisCore
@testable import MetaVisSimulation

final class EXRHDRSanitizeContractTests: XCTestCase {

    private func ensureFFmpegAvailable() throws {
        do {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            p.arguments = ["ffmpeg", "-version"]
            try p.run()
            p.waitUntilExit()
            if p.terminationStatus != 0 {
                throw XCTSkip("ffmpeg not available")
            }
        } catch {
            throw XCTSkip("ffmpeg not available")
        }
    }

    private func runFFmpeg(args: [String], timeoutSeconds: Double) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["ffmpeg"] + args

        let errPipe = Pipe()
        p.standardError = errPipe

        try p.run()

        let start = Date()
        while p.isRunning {
            if Date().timeIntervalSince(start) > timeoutSeconds {
                p.terminate()
                Thread.sleep(forTimeInterval: 0.05)
                let err = errPipe.fileHandleForReading.readDataToEndOfFile()
                let msg = (String(data: err, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                throw NSError(domain: "MetaVisTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "ffmpeg timed out after \(timeoutSeconds)s: \(msg)"])
            }
            Thread.sleep(forTimeInterval: 0.005)
        }

        p.waitUntilExit()

        let err = errPipe.fileHandleForReading.readDataToEndOfFile()
        guard p.terminationStatus == 0 else {
            let msg = (String(data: err, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(domain: "MetaVisTest", code: 2, userInfo: [NSLocalizedDescriptionKey: "ffmpeg failed (\(p.terminationStatus)): \(msg)"])
        }
    }

    private func writeEXRViaFFmpegGBRAPF32LE(rgbaFloat: [Float], width: Int, height: Int, outputURL: URL) throws {
        let expectedFloats = width * height * 4
        precondition(rgbaFloat.count == expectedFloats)

        let rawURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("metavis_test_gbrapf32le_\(UUID().uuidString).raw")
        defer { try? FileManager.default.removeItem(at: rawURL) }

        // Convert interleaved RGBA -> planar gbrapf32le (G, B, R, A) to avoid ffmpeg's
        // rgba128le -> exr conversion path, which is unreliable on some builds.
        let planeSize = width * height
        var planar = [Float](repeating: 0, count: planeSize * 4)
        for i in 0..<planeSize {
            let r = rgbaFloat[(i * 4) + 0]
            let g = rgbaFloat[(i * 4) + 1]
            let b = rgbaFloat[(i * 4) + 2]
            let a = rgbaFloat[(i * 4) + 3]
            planar[(0 * planeSize) + i] = g
            planar[(1 * planeSize) + i] = b
            planar[(2 * planeSize) + i] = r
            planar[(3 * planeSize) + i] = a
        }

        try planar.withUnsafeBytes { Data($0) }.write(to: rawURL, options: [.atomic])

        try runFFmpeg(
            args: [
                "-nostdin",
                "-y",
                "-v", "error",
                "-f", "rawvideo",
                "-pix_fmt", "gbrapf32le",
                "-s", "\(width)x\(height)",
                "-i", rawURL.path,
                "-frames:v", "1",
                "-c:v", "exr",
                "-pix_fmt", "gbrapf32le",
                outputURL.path
            ],
            timeoutSeconds: 20.0
        )
    }

    func testEXRIngest_preservesHDR_and_sanitizesNonFinite() async throws {
        try ensureFFmpegAvailable()

        guard let _ = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal not available")
        }

        // Draft fidelity uses a fixed 256px width; use a matching square size to avoid implicit scaling.
        let w = 256
        let h = 256

        // Synthetic scene-linear EXR payload:
        // - preserves values > 1.0
        // - sanitizes NaN/Inf/-Inf -> 0
        // - clamps huge finite magnitudes to Float16 range (avoid Inf after half conversion)
        var rgba = [Float](repeating: 0, count: w * h * 4)
        func setPixel(_ x: Int, _ y: Int, _ r: Float, _ g: Float, _ b: Float, _ a: Float) {
            let idx = (y * w + x) * 4
            rgba[idx + 0] = r
            rgba[idx + 1] = g
            rgba[idx + 2] = b
            rgba[idx + 3] = a
        }

        setPixel(0, 0, 2.0, 0.0, 0.0, 1.0)
        setPixel(1, 0, 0.0, 3.0, 0.0, 1.0)
        setPixel(2, 0, 0.0, 0.0, 4.0, 1.0)
        setPixel(3, 0, .nan, 1.0, 1.0, 1.0)
        setPixel(0, 1, .infinity, 1.0, 1.0, 1.0)
        setPixel(1, 1, -.infinity, 1.0, 1.0, 1.0)
        setPixel(2, 1, 1e10, 0.0, 0.0, 1.0)

        let tmpEXR = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("metavis_test_hdr_contract_\(UUID().uuidString).exr")
        defer {
            if FileManager.default.fileExists(atPath: tmpEXR.path) {
                try? FileManager.default.removeItem(at: tmpEXR)
            }
        }

        try writeEXRViaFFmpegGBRAPF32LE(rgbaFloat: rgba, width: w, height: h, outputURL: tmpEXR)

        let src = RenderNode(
            name: "EXR",
            shader: "source_texture",
            parameters: [
                "asset_id": .string(tmpEXR.path)
            ]
        )
        let graph = RenderGraph(nodes: [src], rootNodeID: src.id)
        let quality = QualityProfile(name: "EXRHDRContract", fidelity: .draft, resolutionHeight: h, colorDepth: 32)
        let request = RenderRequest(graph: graph, time: .zero, quality: quality)

        let engine = try MetalSimulationEngine()
        try await engine.configure()

        let result = try await engine.render(request: request)
        guard let data = result.imageBuffer else {
            XCTFail("No imageBuffer produced: \(result.metadata)")
            return
        }

        let floats: [Float] = data.withUnsafeBytes { raw in
            let base = raw.bindMemory(to: Float.self)
            return Array(base.prefix(w * h * 4))
        }

        func get(_ x: Int, _ y: Int) -> SIMD4<Float> {
            let idx = (y * w + x) * 4
            return SIMD4<Float>(floats[idx + 0], floats[idx + 1], floats[idx + 2], floats[idx + 3])
        }

        // HDR preservation (within half-float quantization)
        XCTAssertEqual(get(0, 0).x, 2.0, accuracy: 0.01)
        XCTAssertEqual(get(1, 0).y, 3.0, accuracy: 0.01)
        XCTAssertEqual(get(2, 0).z, 4.0, accuracy: 0.01)

        // NaN/Inf sanitization
        XCTAssertEqual(get(3, 0).x, 0.0, accuracy: 0.0001)
        XCTAssertEqual(get(0, 1).x, 0.0, accuracy: 0.0001)
        XCTAssertEqual(get(1, 1).x, 0.0, accuracy: 0.0001)

        // Huge finite values clamp to Float16 max (avoid Inf)
        let clamped = get(2, 1).x
        XCTAssertTrue(clamped.isFinite)
        XCTAssertEqual(clamped, Float(Float16.greatestFiniteMagnitude), accuracy: 1.0)
    }
}
