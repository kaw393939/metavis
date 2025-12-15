import XCTest
import Foundation
import Metal
import MetaVisCore
@testable import MetaVisSimulation

final class EXRFrameDumpRoundtripTests: XCTestCase {

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

    private func runFFmpegAndReadFile(args: [String], timeoutSeconds: Double) throws -> Data {
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

        // Last arg is the output path.
        guard let outPath = args.last else {
            throw NSError(domain: "MetaVisTest", code: 3, userInfo: [NSLocalizedDescriptionKey: "ffmpeg args missing output path"]) 
        }
        return try Data(contentsOf: URL(fileURLWithPath: outPath))
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

        _ = try runFFmpegAndReadFile(
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

    private func decodeEXRToRGBAFloat32(exrURL: URL, width: Int, height: Int) throws -> [Float] {
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("metavis_test_exr_\(UUID().uuidString).gbrapf32le")
        defer {
            if FileManager.default.fileExists(atPath: tmpURL.path) {
                try? FileManager.default.removeItem(at: tmpURL)
            }
        }

        // Decode to planar float32 (gbrapf32le) at the engine's working size and interleave to RGBA in Swift.
        let data = try runFFmpegAndReadFile(
            args: [
                "-nostdin",
                "-y",
                "-v", "error",
                "-i", exrURL.path,
                "-frames:v", "1",
                // Match ClipReader's ingest behavior (scale then format) so the baseline compares like-for-like.
                "-vf", "scale=\(width):\(height):flags=bicubic,format=gbrapf32le",
                "-f", "rawvideo",
                "-pix_fmt", "gbrapf32le",
                tmpURL.path
            ],
            timeoutSeconds: 20.0
        )

        let planeSize = width * height
        let expectedFloats = planeSize * 4
        let expectedBytes = expectedFloats * MemoryLayout<Float>.size
        XCTAssertGreaterThanOrEqual(data.count, expectedBytes)

        let planar: [Float] = data.prefix(expectedBytes).withUnsafeBytes { raw in
            let base = raw.bindMemory(to: Float.self)
            return Array(base.prefix(expectedFloats))
        }

        // gbrapf32le is planar: G, B, R, A.
        var rgba = [Float](repeating: 0, count: expectedFloats)
        for i in 0..<planeSize {
            rgba[(i * 4) + 0] = planar[(2 * planeSize) + i] // R
            rgba[(i * 4) + 1] = planar[(0 * planeSize) + i] // G
            rgba[(i * 4) + 2] = planar[(1 * planeSize) + i] // B
            rgba[(i * 4) + 3] = planar[(3 * planeSize) + i] // A
        }
        return rgba
    }

    func testEXRFrameDump_roundtrip_matchesBaselineAndReloadedEXR() async throws {
        try ensureFFmpegAvailable()

        guard let _ = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal not available")
        }

        let exrURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("assets")
            .appendingPathComponent("exr")
            .appendingPathComponent("CandleGlass.exr")

        if !FileManager.default.fileExists(atPath: exrURL.path) {
            throw XCTSkip("Missing test asset: \(exrURL.path)")
        }

        // Render at deterministic draft size (MetalSimulationEngine uses fixed 256 width in .draft).
        let width = 256
        let height = 256

        let src = RenderNode(
            name: "EXR",
            shader: "source_texture",
            parameters: [
                // Engine resolves this directly as a file path.
                "asset_id": .string(exrURL.path)
            ]
        )
        let graph = RenderGraph(nodes: [src], rootNodeID: src.id)
        let quality = QualityProfile(name: "EXRFrameDump", fidelity: .draft, resolutionHeight: height, colorDepth: 32)
        let request = RenderRequest(graph: graph, time: .zero, quality: quality)

        let engine = try MetalSimulationEngine()
        try await engine.configure()

        let result = try await engine.render(request: request)
        guard let data = result.imageBuffer else {
            XCTFail("No imageBuffer produced: \(result.metadata)")
            return
        }

        let expectedFloats = width * height * 4
        let got: [Float] = data.withUnsafeBytes { raw in
            let base = raw.bindMemory(to: Float.self)
            return Array(base.prefix(expectedFloats))
        }
        XCTAssertEqual(got.count, expectedFloats)

        // 1) Baseline: decode the EXR to float32 RGBA and compare to the engine output.
        // The engine ingests EXR as float16 (rgba16Float), so small half-float quantization deltas are expected.
        let baseline = try decodeEXRToRGBAFloat32(exrURL: exrURL, width: width, height: height)

        let baselineCompare = ImageComparator.compare(bufferA: got, bufferB: baseline, tolerance: 0.02)
        switch baselineCompare {
        case .match:
            break
        case .different(let maxDelta, let avgDelta):
            XCTFail("Rendered output differs from ffmpeg EXR baseline. max=\(maxDelta) avg=\(avgDelta)")
        }

        // 2) Frame dump: write the rendered frame back out as EXR (via ffmpeg) and compare.
        // Store it under Tests/Snapshots so it's easy to inspect.
        let fileURL = URL(fileURLWithPath: #file)
        let testsDir = fileURL.deletingLastPathComponent().deletingLastPathComponent()
        let snapshotsDir = testsDir.appendingPathComponent("Snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: snapshotsDir, withIntermediateDirectories: true)

        let dumpURL = snapshotsDir.appendingPathComponent("FrameDump_EXR_CandleGlass_256_ffmpeg.exr")
        try? FileManager.default.removeItem(at: dumpURL)
        try writeEXRViaFFmpegGBRAPF32LE(rgbaFloat: got, width: width, height: height, outputURL: dumpURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dumpURL.path))

        let dumpedRGBA = try decodeEXRToRGBAFloat32(exrURL: dumpURL, width: width, height: height)
        XCTAssertEqual(dumpedRGBA.count, got.count)

        // This should be extremely close; allow for tiny fp noise.
        let roundtripCompare = ImageComparator.compare(bufferA: got, bufferB: dumpedRGBA, tolerance: 1e-6)
        switch roundtripCompare {
        case .match:
            break
        case .different(let maxDelta, let avgDelta):
            XCTFail("Dumped EXR did not roundtrip. max=\(maxDelta) avg=\(avgDelta) (dump=\(dumpURL.lastPathComponent))")
        }
    }
}
