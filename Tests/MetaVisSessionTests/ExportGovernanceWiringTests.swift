import XCTest
import Foundation
import AVFoundation
import MetaVisCore
import MetaVisTimeline
@testable import MetaVisExport
@testable import MetaVisSession

final class ExportGovernanceWiringTests: XCTestCase {

    actor ValidatingCapturingExporter: VideoExporting {
        private(set) var lastTimeline: Timeline?
        private(set) var lastOutputURL: URL?
        private(set) var lastQuality: QualityProfile?
        private(set) var lastFrameRate: Int?
        private(set) var lastCodec: AVVideoCodecType?
        private(set) var lastAudioPolicy: AudioPolicy?
        private(set) var lastGovernance: ExportGovernance?

        func export(
            timeline: Timeline,
            to outputURL: URL,
            quality: QualityProfile,
            frameRate: Int,
            codec: AVVideoCodecType,
            audioPolicy: AudioPolicy,
            governance: ExportGovernance
        ) async throws {
            lastTimeline = timeline
            lastOutputURL = outputURL
            lastQuality = quality
            lastFrameRate = frameRate
            lastCodec = codec
            lastAudioPolicy = audioPolicy
            lastGovernance = governance

            try VideoExporter.validateExport(quality: quality, governance: governance)
        }
    }

    func testExportMoviePassesGovernancePlanAndLicense() async throws {
        let entitlements = EntitlementManager(initialPlan: .free)
        let license = ProjectLicense(ownerId: "u", maxExportResolution: 1440, requiresWatermark: false, allowOpenEXR: false)
        let state = ProjectState(config: ProjectConfig(name: "P", license: license))
        let session = ProjectSession(initialState: state, entitlements: entitlements)

        let exporter = ValidatingCapturingExporter()
        let quality = QualityProfile(name: "q", fidelity: .draft, resolutionHeight: 1080, colorDepth: 10)
        let url = URL(fileURLWithPath: "/tmp/metavis_session_export_wiring.mov")

        try await session.exportMovie(using: exporter, to: url, quality: quality, frameRate: 24, codec: .hevc, audioPolicy: .auto)

        let governance = await exporter.lastGovernance
        let lastOutputURL = await exporter.lastOutputURL
        let lastQuality = await exporter.lastQuality
        let lastFrameRate = await exporter.lastFrameRate
        let lastCodec = await exporter.lastCodec
        let lastAudioPolicy = await exporter.lastAudioPolicy

        XCTAssertEqual(governance?.userPlan, .free)
        XCTAssertEqual(governance?.projectLicense, license)
        XCTAssertEqual(lastOutputURL, url)
        XCTAssertEqual(lastQuality, quality)
        XCTAssertEqual(lastFrameRate, 24)
        XCTAssertEqual(lastCodec, AVVideoCodecType.hevc)
        XCTAssertEqual(lastAudioPolicy, .auto)
    }

    func testExportMovieFailsWhenResolutionExceedsPlanCap() async {
        let entitlements = EntitlementManager(initialPlan: .free) // 1080
        let license = ProjectLicense(ownerId: "u", maxExportResolution: 4320, requiresWatermark: false, allowOpenEXR: false)
        let state = ProjectState(config: ProjectConfig(name: "P", license: license))
        let session = ProjectSession(initialState: state, entitlements: entitlements)

        let exporter = ValidatingCapturingExporter()
        let quality = QualityProfile(name: "q", fidelity: .high, resolutionHeight: 2160, colorDepth: 10)
        let url = URL(fileURLWithPath: "/tmp/metavis_session_export_wiring.mov")

        do {
            try await session.exportMovie(using: exporter, to: url, quality: quality)
            XCTFail("Expected resolutionNotAllowed")
        } catch let err as ExportGovernanceError {
            switch err {
            case .resolutionNotAllowed(let requestedHeight, let maxAllowedHeight):
                XCTAssertEqual(requestedHeight, 2160)
                XCTAssertEqual(maxAllowedHeight, 1080)
            default:
                XCTFail("Unexpected ExportGovernanceError: \(err)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testExportMovieAppliesWatermarkWhenRequired() async throws {
        let entitlements = EntitlementManager(initialPlan: .pro)
        let license = ProjectLicense(ownerId: "u", maxExportResolution: 4320, requiresWatermark: true, allowOpenEXR: false)
        let state = ProjectState(config: ProjectConfig(name: "P", license: license))
        let session = ProjectSession(initialState: state, entitlements: entitlements)

        let exporter = ValidatingCapturingExporter()
        let quality = QualityProfile(name: "q", fidelity: .high, resolutionHeight: 1080, colorDepth: 10)
        let url = URL(fileURLWithPath: "/tmp/metavis_session_export_wiring.mov")

        try await session.exportMovie(using: exporter, to: url, quality: quality)

        let governance = await exporter.lastGovernance
        XCTAssertEqual(governance?.projectLicense?.requiresWatermark, true)
        XCTAssertEqual(governance?.watermarkSpec?.style, .diagonalStripes)
    }
}
