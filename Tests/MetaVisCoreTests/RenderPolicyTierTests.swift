import XCTest
import MetaVisCore

final class RenderPolicyTierTests: XCTestCase {

    func testParse() {
        XCTAssertEqual(RenderPolicyTier.parse("consumer"), .consumer)
        XCTAssertEqual(RenderPolicyTier.parse(" Creator \n"), .creator)
        XCTAssertEqual(RenderPolicyTier.parse("STUDIO"), .studio)
        XCTAssertNil(RenderPolicyTier.parse("unknown"))
    }

    func testCatalogEdgePolicies() {
        XCTAssertEqual(RenderPolicyCatalog.policy(for: .consumer).edgePolicy, .autoResizeBilinear)
        XCTAssertEqual(RenderPolicyCatalog.policy(for: .creator).edgePolicy, .autoResizeBicubic)
        XCTAssertEqual(RenderPolicyCatalog.policy(for: .studio).edgePolicy, .requireExplicitAdapters)
    }

    func testDocsExistForAllTiers() {
        // Keep this lightweight: ensure the repo documents each tier.
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let base = root.appendingPathComponent("Docs/policies/render")
        for tier in RenderPolicyTier.allCases {
            let url = base.appendingPathComponent("\(tier.rawValue).md")
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Missing policy doc: \(url.path)")
        }
    }
}
