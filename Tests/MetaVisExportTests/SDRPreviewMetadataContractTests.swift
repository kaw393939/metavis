import XCTest
import AVFoundation

import MetaVisCore
import MetaVisTimeline
import MetaVisExport
import MetaVisSimulation

final class SDRPreviewMetadataContractTests: XCTestCase {

    func test_export_tags_rec709_color_metadata_consistently() async throws {
        // Deterministic, short export.
        let timeline = Timeline(
            tracks: [
                Track(
                    name: "Video",
                    kind: .video,
                    clips: [
                        Clip(
                            name: "Macbeth",
                            asset: AssetReference(sourceFn: "ligm://fx_macbeth"),
                            startTime: .zero,
                            duration: Time(seconds: 1.0)
                        )
                    ]
                )
            ],
            duration: Time(seconds: 1.0)
        )

        let outURL = TestOutputs.url(for: "sdr_preview_metadata_contract", quality: "256p_10bit", ext: "mov")

        let quality = QualityProfile(name: "Test", fidelity: .high, resolutionHeight: 256, colorDepth: 10)
        let engine = try MetalSimulationEngine()
        try await engine.configure()
        let exporter = VideoExporter(engine: engine, trace: NoOpTraceSink())

        try await exporter.export(
            timeline: timeline,
            to: outURL,
            quality: quality,
            frameRate: 24,
            codec: .hevc,
            audioPolicy: .forbidden,
            governance: .none
        )

        let report = try await inspectVideoMetadata(at: outURL)

        // These keys are expected to be present due to explicit AVVideoColorPropertiesKey tagging.
        XCTAssertEqual(report.colorPrimaries, "ITU_R_709_2")
        XCTAssertEqual(report.transferFunction, "ITU_R_709_2")
        XCTAssertEqual(report.yCbCrMatrix, "ITU_R_709_2")
        XCTAssertEqual(report.isHDR, false)
    }

    private struct VideoTrackReport: Sendable {
        var colorPrimaries: String?
        var transferFunction: String?
        var yCbCrMatrix: String?
        var isHDR: Bool?
    }

    private func inspectVideoMetadata(at url: URL) async throws -> VideoTrackReport {
        let asset = AVURLAsset(url: url)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let vt = videoTracks.first else {
            throw NSError(domain: "MetaVisTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "No video track"])
        }

        let formatDescriptions = try await vt.load(.formatDescriptions)
        guard let fd = formatDescriptions.first else {
            return VideoTrackReport()
        }

        var colorPrimaries: String?
        var transferFunction: String?
        var yCbCrMatrix: String?
        var isHDR: Bool?

        if let ext = CMFormatDescriptionGetExtensions(fd) as? [String: Any] {
            colorPrimaries = ext[kCMFormatDescriptionExtension_ColorPrimaries as String] as? String
            transferFunction = ext[kCMFormatDescriptionExtension_TransferFunction as String] as? String
            yCbCrMatrix = ext[kCMFormatDescriptionExtension_YCbCrMatrix as String] as? String
        }

        if let tf = transferFunction?.lowercased() {
            if tf.contains("2100") || tf.contains("pq") || tf.contains("hlg") {
                isHDR = true
            } else {
                isHDR = false
            }
        }

        return VideoTrackReport(
            colorPrimaries: colorPrimaries,
            transferFunction: transferFunction,
            yCbCrMatrix: yCbCrMatrix,
            isHDR: isHDR
        )
    }
}
