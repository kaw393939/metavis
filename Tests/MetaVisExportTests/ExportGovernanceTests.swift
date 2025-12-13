import XCTest
import MetaVisCore
@testable import MetaVisExport

final class ExportGovernanceTests: XCTestCase {

    func testValidateExport_allowsWhenNoGovernance() throws {
        let quality = QualityProfile(name: "q", fidelity: .master, resolutionHeight: 2160, colorDepth: 10)
        try VideoExporter.validateExport(quality: quality, governance: .none)
    }

    func testValidateExport_blocksWhenUserPlanResolutionExceeded() {
        let quality = QualityProfile(name: "q", fidelity: .master, resolutionHeight: 2160, colorDepth: 10)
        let governance = ExportGovernance(userPlan: UserPlan(name: "Free", maxProjectCount: 1, allowedProjectTypes: [.basic], maxResolution: 1080))

        XCTAssertThrowsError(try VideoExporter.validateExport(quality: quality, governance: governance)) { error in
            XCTAssertEqual(error as? ExportGovernanceError, .resolutionNotAllowed(requestedHeight: 2160, maxAllowedHeight: 1080))
        }
    }

    func testValidateExport_blocksWhenProjectLicenseResolutionExceeded() {
        let quality = QualityProfile(name: "q", fidelity: .master, resolutionHeight: 2160, colorDepth: 10)
        let license = ProjectLicense(ownerId: "u", maxExportResolution: 1440, requiresWatermark: false, allowOpenEXR: false)
        let governance = ExportGovernance(projectLicense: license)

        XCTAssertThrowsError(try VideoExporter.validateExport(quality: quality, governance: governance)) { error in
            XCTAssertEqual(error as? ExportGovernanceError, .resolutionNotAllowed(requestedHeight: 2160, maxAllowedHeight: 1440))
        }
    }

    func testValidateExport_usesMostRestrictiveResolutionCapAcrossPlanAndLicense() {
        let quality = QualityProfile(name: "q", fidelity: .master, resolutionHeight: 2160, colorDepth: 10)
        let plan = UserPlan(name: "Pro?", maxProjectCount: 999, allowedProjectTypes: [.basic, .cinema, .lab, .commercial], maxResolution: 2000)
        let license = ProjectLicense(ownerId: "u", maxExportResolution: 1440, requiresWatermark: false, allowOpenEXR: false)
        let governance = ExportGovernance(userPlan: plan, projectLicense: license)

        XCTAssertThrowsError(try VideoExporter.validateExport(quality: quality, governance: governance)) { error in
            XCTAssertEqual(error as? ExportGovernanceError, .resolutionNotAllowed(requestedHeight: 2160, maxAllowedHeight: 1440))
        }
    }

    func testValidateExport_blocksWhenWatermarkRequired() {
        let quality = QualityProfile(name: "q", fidelity: .master, resolutionHeight: 1080, colorDepth: 10)
        let license = ProjectLicense(ownerId: "u", maxExportResolution: 1080, requiresWatermark: true, allowOpenEXR: false)
        let governance = ExportGovernance(projectLicense: license)

        XCTAssertThrowsError(try VideoExporter.validateExport(quality: quality, governance: governance)) { error in
            XCTAssertEqual(error as? ExportGovernanceError, .watermarkRequired)
        }
    }

    func testValidateExport_allowsWhenWatermarkRequiredAndSpecProvided() throws {
        let quality = QualityProfile(name: "q", fidelity: .master, resolutionHeight: 1080, colorDepth: 10)
        let license = ProjectLicense(ownerId: "u", maxExportResolution: 1080, requiresWatermark: true, allowOpenEXR: false)
        let governance = ExportGovernance(projectLicense: license, watermarkSpec: .diagonalStripesDefault)

        try VideoExporter.validateExport(quality: quality, governance: governance)
    }
}
