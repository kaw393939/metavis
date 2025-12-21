import XCTest
import CoreVideo
import MetaVisPerception

final class DepthSidecarReadinessTests: XCTestCase {

    private func requireAssetCPath() throws -> URL {
        let env = ProcessInfo.processInfo.environment
        guard let raw = env["METAVIS_LIDAR_ASSET_C_MOVIE"], !raw.isEmpty else {
            throw XCTSkip("Set METAVIS_LIDAR_ASSET_C_MOVIE=/absolute/path/to/AssetC.mov to enable LiDAR readiness checks")
        }
        return URL(fileURLWithPath: raw).standardizedFileURL
    }

    func test_lidar_assetC_sidecar_presence_or_skip() throws {
        let movieURL = try requireAssetCPath()
        if !FileManager.default.fileExists(atPath: movieURL.path) {
            throw XCTSkip("Asset C movie not found at: \(movieURL.path)")
        }

        let base = movieURL.deletingPathExtension()
        let manifestURL = base.appendingPathExtension("depth.v1.json")
        let dataURL = base.appendingPathExtension("depth.v1.bin")

        // If the v1 JSON+BIN sidecar exists, validate that we can decode at least one frame.
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            // `DepthSidecarV1Reader` already validates that the referenced bin exists.
            let reader = try DepthSidecarV1Reader(manifestURL: manifestURL)
            let pb0 = try reader.readDepthFrame(index: 0)

            XCTAssertEqual(CVPixelBufferGetWidth(pb0), reader.manifest.width)
            XCTAssertEqual(CVPixelBufferGetHeight(pb0), reader.manifest.height)

            switch reader.manifest.pixelFormat {
            case .r16f:
                XCTAssertEqual(CVPixelBufferGetPixelFormatType(pb0), kCVPixelFormatType_DepthFloat16)
            case .r32f:
                XCTAssertEqual(CVPixelBufferGetPixelFormatType(pb0), kCVPixelFormatType_OneComponent32Float)
            }

            // Keep alignment/relink correctness tests deferred until we have a canonical Asset C capture.
            throw XCTSkip("Depth sidecar v1 decodes (\(manifestURL.lastPathComponent), \(dataURL.lastPathComponent)); alignment/relink validation activates once Asset C is finalized")
        }

        // If we have other sidecar formats, acknowledge presence but skip (not yet implemented).
        if let sidecar = DepthSidecarLocatorV1.firstExistingSidecarURL(forVideoURL: movieURL) {
            throw XCTSkip("Depth sidecar present (\(sidecar.lastPathComponent)); v1 JSON+BIN decoding activates when \(manifestURL.lastPathComponent) is available")
        }

        let candidates = DepthSidecarLocatorV1.candidateSidecarURLs(forVideoURL: movieURL)
            .map { $0.lastPathComponent }
            .joined(separator: ", ")
        XCTFail("No depth sidecar found next to Asset C movie. Expected one of: \(candidates)")
    }
}
