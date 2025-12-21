import XCTest
@testable import MetaVisCore

final class LicenseTests: XCTestCase {
    
    func testLicenseTierComparison() {
        // Free < Pro < Studio < Enterprise
        XCTAssertTrue(LicenseTier.free < .pro)
        XCTAssertTrue(LicenseTier.pro < .studio)
        XCTAssertTrue(LicenseTier.studio < .enterprise)
        
        XCTAssertFalse(LicenseTier.pro < .free)
        XCTAssertFalse(LicenseTier.studio < .pro)
        
        // Equality
        XCTAssertTrue(LicenseTier.pro >= .pro)
    }
    
    func testFeatureGating() async {
        let manager = LicenseManager(tier: .free)
        
        // Free tier checks
        let allowed4K = await manager.isAllowed(.export4K)
        let allowedGen = await manager.isAllowed(.aiGenerativeVideo)
        
        XCTAssertFalse(allowed4K)
        XCTAssertFalse(allowedGen)
        
        // Upgrade to Pro
        await manager.setTier(.pro)
        let allowed4KPro = await manager.isAllowed(.export4K)
        let allowedProRes = await manager.isAllowed(.exportProRes)
        let allowedGenPro = await manager.isAllowed(.aiGenerativeVideo)
        
        XCTAssertTrue(allowed4KPro)
        XCTAssertTrue(allowedProRes)
        XCTAssertFalse(allowedGenPro) // Studio only
        
        // Upgrade to Studio
        await manager.setTier(.studio)
        let allowedGenStudio = await manager.isAllowed(.aiGenerativeVideo)
        XCTAssertTrue(allowedGenStudio)
    }
    
    func testValidationThrowing() async {
        let manager = LicenseManager(tier: .free)
        
        do {
            try await manager.validate(.export4K)
            XCTFail("Should have thrown")
        } catch {
             // Success
        }
        
        await manager.setTier(.pro)
        
        do {
            try await manager.validate(.export4K)
        } catch {
            XCTFail("Should not have thrown: \(error)")
        }
    }
}
