import XCTest
import Foundation
import AVFoundation
import CoreVideo
import MetaVisPerception

/// Env-gated harness for validating real LiDAR Asset C once it exists.
///
/// This is intentionally conservative:
/// - It does not attempt to validate geometric depth->RGB registration yet.
/// - It validates that the sidecar can be decoded and that depth values look sane and governed.
final class DepthAssetCAlignmentHarnessTests: XCTestCase {

    private func requireAssetCPath() throws -> URL {
        let env = ProcessInfo.processInfo.environment
        guard let raw = env["METAVIS_LIDAR_ASSET_C_MOVIE"], !raw.isEmpty else {
            throw XCTSkip("Set METAVIS_LIDAR_ASSET_C_MOVIE=/absolute/path/to/AssetC.mov to enable LiDAR harness checks")
        }
        return URL(fileURLWithPath: raw).standardizedFileURL
    }

    private func readFirstVideoFrameAndPTSSeconds(url: URL) async throws -> (CVPixelBuffer, Double) {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            throw XCTSkip("Asset C has no video track")
        }

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw XCTSkip("Cannot decode Asset C video frames")
        }
        reader.add(output)
        guard reader.startReading() else {
            throw XCTSkip("Cannot start reading Asset C")
        }

        guard let sb = output.copyNextSampleBuffer(), let pb = CMSampleBufferGetImageBuffer(sb) else {
            throw XCTSkip("No decodable frames in Asset C")
        }
        let pts = CMSampleBufferGetPresentationTimeStamp(sb)
        let t = pts.isValid ? pts.seconds : 0.0
        return (pb, t)
    }

    func test_lidar_assetC_depth_sidecar_v1_decodes_and_is_reasonable_or_skip() async throws {
        let movieURL = try requireAssetCPath()
        if !FileManager.default.fileExists(atPath: movieURL.path) {
            throw XCTSkip("Asset C movie not found at: \(movieURL.path)")
        }

        let base = movieURL.deletingPathExtension()
        let manifestURL = base.appendingPathExtension("depth.v1.json")

        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw XCTSkip("No v1 depth sidecar found (expected \(manifestURL.lastPathComponent)).")
        }

        let reader = try DepthSidecarV1Reader(manifestURL: manifestURL)

        let (rgb, t) = try await readFirstVideoFrameAndPTSSeconds(url: movieURL)
        let depth = try reader.readDepthFrame(at: t)

        // Basic sanity: dimensions should match if the sidecar is aligned/resampled.
        XCTAssertEqual(CVPixelBufferGetWidth(depth), CVPixelBufferGetWidth(rgb))
        XCTAssertEqual(CVPixelBufferGetHeight(depth), CVPixelBufferGetHeight(rgb))

        let device = DepthDevice()
        try await device.warmUp()

        let res = try await device.depthResult(in: rgb, depthSample: depth, confidenceSample: nil)

        XCTAssertNotNil(res.depth)
        XCTAssertFalse(res.evidenceConfidence.reasons.contains(.depth_missing))
        XCTAssertFalse(res.evidenceConfidence.reasons.contains(.depth_invalid_range))

        // Expect at least some valid pixels; threshold is intentionally low until we see a real capture.
        XCTAssertGreaterThan(res.metrics.validPixelRatio, 0.001)

        // If we got sane depth, min/max should be present and ordered.
        if let minD = res.metrics.minDepthMeters, let maxD = res.metrics.maxDepthMeters {
            XCTAssertGreaterThan(minD, 0.0)
            XCTAssertLessThanOrEqual(minD, maxD)
            XCTAssertLessThanOrEqual(maxD, 50.0)
        } else {
            XCTFail("Expected min/max depth metrics")
        }

        throw XCTSkip("Harness ran: depth decoded and passed sanity checks. Alignment/relink validation activates once Asset C calibration + proxy/full-res pairs exist.")
    }
}
