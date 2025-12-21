import XCTest
import MetaVisCore
import MetaVisTimeline
@testable import MetaVisSession

final class CommandExecutorTargetingTests: XCTestCase {

    func testApplyColorGradeTargetsClipIdNotFirstClip() async {
        let clipA = Clip(
            name: "A",
            asset: AssetReference(sourceFn: "ligm://video/smpte_bars"),
            startTime: .zero,
            duration: Time(seconds: 1.0)
        )
        let clipB = Clip(
            name: "B",
            asset: AssetReference(sourceFn: "ligm://video/macbeth"),
            startTime: Time(seconds: 1.0),
            duration: Time(seconds: 1.0)
        )
        let track = Track(name: "V", kind: .video, clips: [clipA, clipB])
        var timeline = Timeline(tracks: [track], duration: Time(seconds: 2.0))

        let executor = CommandExecutor(trace: NoOpTraceSink())
        await executor.execute(
            [.applyColorGrade(target: .clipId(clipB.id), gradeTarget: "clip", params: ["exposure": 0.25])],
            in: &timeline
        )

        let effectsA = timeline.tracks[0].clips[0].effects
        let effectsB = timeline.tracks[0].clips[1].effects

        XCTAssertNil(effectsA.first(where: { $0.id == "mv.colorGrade" }))
        let graded = effectsB.first(where: { $0.id == "mv.colorGrade" })
        XCTAssertNotNil(graded)
        XCTAssertEqual(graded?.parameters["exposure"], .float(0.25))
    }

    func testBladeSplitsClipAndAdjustsSecondOffset() async {
        var clip = Clip(
            name: "Zone",
            asset: AssetReference(sourceFn: "ligm://video/zone_plate?speed=1.0"),
            startTime: Time(seconds: 10.0),
            duration: Time(seconds: 5.0),
            offset: Time(seconds: 2.0)
        )
        // Put a transition on to ensure we preserve at least one side.
        clip.transitionIn = .crossfade(duration: Time(seconds: 0.5))
        clip.transitionOut = .crossfade(duration: Time(seconds: 0.5))

        let track = Track(name: "V", kind: .video, clips: [clip])
        var timeline = Timeline(tracks: [track], duration: Time(seconds: 15.0))

        let executor = CommandExecutor(trace: NoOpTraceSink())
        await executor.execute(
            [.bladeClip(target: .clipId(clip.id), atSeconds: 12.0)],
            in: &timeline
        )

        XCTAssertEqual(timeline.tracks[0].clips.count, 2)
        let first = timeline.tracks[0].clips[0]
        let second = timeline.tracks[0].clips[1]

        XCTAssertEqual(first.startTime.seconds, 10.0, accuracy: 0.0001)
        XCTAssertEqual(first.duration.seconds, 2.0, accuracy: 0.0001)
        XCTAssertEqual(first.offset.seconds, 2.0, accuracy: 0.0001)
        XCTAssertNotNil(first.transitionIn)
        XCTAssertNil(first.transitionOut)

        XCTAssertEqual(second.startTime.seconds, 12.0, accuracy: 0.0001)
        XCTAssertEqual(second.duration.seconds, 3.0, accuracy: 0.0001)
        // Second clip offset should advance by the first segment duration.
        XCTAssertEqual(second.offset.seconds, 4.0, accuracy: 0.0001)
        XCTAssertNil(second.transitionIn)
        XCTAssertNotNil(second.transitionOut)
    }
}
