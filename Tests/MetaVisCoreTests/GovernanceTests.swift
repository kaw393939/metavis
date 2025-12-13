import XCTest
import MetaVisCore

final class GovernanceTests: XCTestCase {
    
    func testDefaultPlans() {
        let free = UserPlan.free
        XCTAssertEqual(free.maxProjectCount, 3)
        XCTAssertTrue(free.allowedProjectTypes.contains(.basic))
        XCTAssertFalse(free.allowedProjectTypes.contains(.cinema))
        
        let pro = UserPlan.pro
        XCTAssertEqual(pro.maxProjectCount, Int.max)
        XCTAssertTrue(pro.allowedProjectTypes.contains(.cinema))
    }
    
    func testProjectLicenseCodable() throws {
        let license = ProjectLicense(ownerId: "user_123", maxExportResolution: 2160, requiresWatermark: false)
        let data = try JSONEncoder().encode(license)
        let decoded = try JSONDecoder().decode(ProjectLicense.self, from: data)
        
        XCTAssertEqual(decoded.ownerId, "user_123")
        XCTAssertEqual(decoded.maxExportResolution, 2160)
        XCTAssertFalse(decoded.requiresWatermark)
    }
}
