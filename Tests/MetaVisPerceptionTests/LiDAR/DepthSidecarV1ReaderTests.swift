import XCTest
import Foundation
import CoreVideo
import MetaVisPerception

final class DepthSidecarV1ReaderTests: XCTestCase {

    private func makeTempDir() throws -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let dir = base.appendingPathComponent("metavis_depth_sidecar_v1_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeR16FFrame(values: [Float], to data: inout Data) {
        for f in values {
            let u = Float16(f).bitPattern
            var le = u.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
    }

    func test_reader_loads_manifest_and_reads_frames_by_time() throws {
        let dir = try makeTempDir()

        let manifestURL = dir.appendingPathComponent("AssetC.depth.v1.json")
        let dataURL = dir.appendingPathComponent("AssetC.depth.v1.bin")

        // 2x2, 2 frames, r16f.
        let manifest = DepthSidecarV1Manifest(
            width: 2,
            height: 2,
            pixelFormat: .r16f,
            frameCount: 2,
            startTimeSeconds: 0.0,
            frameDurationSeconds: 0.5,
            dataFile: "AssetC.depth.v1.bin",
            endianness: .little,
            calibration: nil
        )

        let json = try JSONEncoder().encode(manifest)
        try json.write(to: manifestURL)

        var bin = Data()
        writeR16FFrame(values: [1, 2, 3, 4], to: &bin)
        writeR16FFrame(values: [5, 6, 7, 8], to: &bin)
        try bin.write(to: dataURL)

        let reader = try DepthSidecarV1Reader(manifestURL: manifestURL)

        // Time near 0 -> frame 0
        let pb0 = try reader.readDepthFrame(at: 0.1)
        XCTAssertEqual(CVPixelBufferGetWidth(pb0), 2)
        XCTAssertEqual(CVPixelBufferGetHeight(pb0), 2)

        // Time near 0.5 -> frame 1
        let pb1 = try reader.readDepthFrame(at: 0.6)

        func readAllR16F(_ pb: CVPixelBuffer) -> [Float] {
            CVPixelBufferLockBaseAddress(pb, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }

            let w = CVPixelBufferGetWidth(pb)
            let h = CVPixelBufferGetHeight(pb)
            let bpr = CVPixelBufferGetBytesPerRow(pb)
            let base = CVPixelBufferGetBaseAddress(pb)!

            var out: [Float] = []
            out.reserveCapacity(w * h)

            for y in 0..<h {
                let row = base.advanced(by: y * bpr).assumingMemoryBound(to: UInt16.self)
                for x in 0..<w {
                    out.append(Float(Float16(bitPattern: row[x])))
                }
            }
            return out
        }

        XCTAssertEqual(readAllR16F(pb0), [1, 2, 3, 4])
        XCTAssertEqual(readAllR16F(pb1), [5, 6, 7, 8])
    }
}
