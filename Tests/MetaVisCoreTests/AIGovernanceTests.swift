import XCTest
import MetaVisCore

final class AIGovernanceTests: XCTestCase {

    func test_defaultPolicy_is_local_only() {
        let policy = AIUsagePolicy.localOnlyDefault
        XCTAssertEqual(policy.mode, .off)

        let privacy = PrivacyPolicy()
        XCTAssertFalse(policy.allowsNetworkRequests(privacy: privacy))
        XCTAssertFalse(policy.allowsImages(privacy: privacy))
        XCTAssertFalse(policy.allowsVideo(privacy: privacy))
    }

    func test_textOnly_allows_network_without_media_upload_privileges() {
        let policy = AIUsagePolicy(mode: .textOnly)
        let privacy = PrivacyPolicy(allowRawMediaUpload: false, allowDeliverablesUpload: false)
        XCTAssertTrue(policy.allowsNetworkRequests(privacy: privacy))
        XCTAssertFalse(policy.allowsImages(privacy: privacy))
        XCTAssertFalse(policy.allowsVideo(privacy: privacy))
    }

    func test_textImagesAndVideo_requires_deliverables_upload_when_deliverablesOnly() {
        let policy = AIUsagePolicy(mode: .textImagesAndVideo, mediaSource: .deliverablesOnly)

        XCTAssertFalse(policy.allowsNetworkRequests(privacy: PrivacyPolicy(allowRawMediaUpload: true, allowDeliverablesUpload: false)))
        XCTAssertTrue(policy.allowsNetworkRequests(privacy: PrivacyPolicy(allowRawMediaUpload: false, allowDeliverablesUpload: true)))
    }
}
