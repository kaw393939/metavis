import XCTest
import MetaVisCore

final class PrivacyPolicyTests: XCTestCase {

    func testDefaultsDisallowRawMediaUpload() {
        let policy = PrivacyPolicy()
        XCTAssertFalse(policy.allowRawMediaUpload)
        XCTAssertFalse(policy.allowDeliverablesUpload)
    }
}
