import XCTest
import Foundation
import MetaVisExport
import MetaVisCore

final class DeliverableManifestBackCompatTests: XCTestCase {

    func testDecodeSchemaV2WithoutExpandedQCFields() throws {
        // Minimal v2-like payload (no qcContentReport/qcMetadataReport/qcSidecarReport).
        let json = """
        {
          "schemaVersion": 2,
          "createdAt": "2025-01-01T00:00:00Z",
          "deliverable": {"id":"youtube_master","displayName":"YouTube Master"},
          "timeline": {"durationSeconds": 2.0, "trackCount": 1, "clipCount": 1},
          "quality": {"name":"Master 4K","fidelity":"master","resolutionHeight":2160,"colorDepth":10},
          "frameRate": 24,
          "codec": "hvc1",
          "audioPolicy": "required",
          "governance": {
            "userPlan": {"name":"Pro","maxProjectCount": 9223372036854775807, "allowedProjectTypes": ["basic","cinema","lab"], "maxResolution": 4320},
            "projectLicense": {"licenseId":"00000000-0000-0000-0000-000000000000","ownerId":"anonymous","maxExportResolution":1080,"requiresWatermark":false,"allowOpenEXR":false},
            "watermarkSpec": null
          },
          "qcPolicy": {
            "video": {
              "minDurationSeconds": 1.0,
              "maxDurationSeconds": 3.0,
              "expectedWidth": 3840,
              "expectedHeight": 2160,
              "expectedNominalFrameRate": 24.0,
              "minVideoSampleCount": 1
            },
            "requireAudioTrack": true,
            "requireAudioNotSilent": true,
            "audioSampleSeconds": 0.5,
            "minAudioPeak": 0.0005
          },
          "qcReport": {
            "durationSeconds": 2.0,
            "width": 3840,
            "height": 2160,
            "nominalFrameRate": 24.0,
            "estimatedDataRate": 1000.0,
            "videoSampleCount": 48
          },
          "sidecars": []
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let manifest = try decoder.decode(DeliverableManifest.self, from: Data(json.utf8))

        XCTAssertEqual(manifest.schemaVersion, 2)
        XCTAssertNil(manifest.qcContentReport)
        XCTAssertNil(manifest.qcMetadataReport)
        XCTAssertNil(manifest.qcSidecarReport)
        XCTAssertEqual(manifest.sidecars.count, 0)
    }
}
