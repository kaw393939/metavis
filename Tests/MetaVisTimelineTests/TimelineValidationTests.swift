import XCTest
import MetaVisTimeline
import MetaVisCore

final class TimelineValidationTests: XCTestCase {
    func testValidateDetectsOverlappingClipsOnSameTrack() throws {
        let asset = AssetReference(sourceFn: "file:///tmp/test.mov")
        let c1 = Clip(name: "a", asset: asset, startTime: Time(seconds: 0), duration: Time(seconds: 10))
        let c2 = Clip(name: "b", asset: asset, startTime: Time(seconds: 5), duration: Time(seconds: 10))
        let track = Track(name: "V1", kind: .video, clips: [c1, c2])
        let timeline = Timeline(tracks: [track], duration: Time(seconds: 20))

        let issues = timeline.validate()
        XCTAssertEqual(issues.count, 1)
    }

    func testValidateAllowsTouchingClips() throws {
        let asset = AssetReference(sourceFn: "file:///tmp/test.mov")
        let c1 = Clip(name: "a", asset: asset, startTime: Time(seconds: 0), duration: Time(seconds: 10))
        let c2 = Clip(name: "b", asset: asset, startTime: Time(seconds: 10), duration: Time(seconds: 10))
        let track = Track(name: "V1", kind: .video, clips: [c1, c2])
        let timeline = Timeline(tracks: [track], duration: Time(seconds: 20))

        let issues = timeline.validate()
        XCTAssertTrue(issues.isEmpty)
    }
}
