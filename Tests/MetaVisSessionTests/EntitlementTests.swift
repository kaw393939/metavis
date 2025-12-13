import XCTest
import MetaVisCore
@testable import MetaVisSession

final class EntitlementTests: XCTestCase {
    
    func testFreePlanRestrictions() {
        let manager = EntitlementManager(initialPlan: .free)
        
        // Allowed
        XCTAssertTrue(manager.canCreateProject(type: .basic, currentCount: 0))
        
        // Blocked by Limit
        XCTAssertFalse(manager.canCreateProject(type: .basic, currentCount: 3))
        
        // Blocked by Type
        XCTAssertFalse(manager.canCreateProject(type: .cinema, currentCount: 0))
        
        // Blocked by Resolution (Free is 1080)
        XCTAssertFalse(manager.canExport(resolutionHeight: 2160))
    }
    
    func testUnlockCode() {
        let manager = EntitlementManager(initialPlan: .free)
        
        // Unlock Pro
        let success = manager.applyUnlockCode("UNLOCK_PRO_2025")
        XCTAssertTrue(success)
        
        // Pro Features
        XCTAssertTrue(manager.canCreateProject(type: .cinema, currentCount: 10))
        XCTAssertTrue(manager.canExport(resolutionHeight: 2160))
    }
}
