import XCTest
import MetaVisCore
import MetaVisTimeline
import MetaVisServices
@testable import MetaVisSession

final class IntentEditActionsE2ETests: XCTestCase {

    func testApplyIntent_cutBladesFirstVideoClip() async {
        let clip = Clip(
            name: "Clip",
            asset: AssetReference(sourceFn: "ligm://video/zone_plate?speed=1.0"),
            startTime: .zero,
            duration: Time(seconds: 4.0)
        )
        let track = Track(name: "V", kind: .video, clips: [clip])
        let timeline = Timeline(tracks: [track], duration: Time(seconds: 4.0))

        let session = ProjectSession(initialState: ProjectState(timeline: timeline), trace: NoOpTraceSink())
        await session.applyIntent(UserIntent(action: .cut, target: "clip", params: ["time": 1.5]))

        let updated = await session.state.timeline
        XCTAssertEqual(updated.tracks[0].clips.count, 2)
        XCTAssertEqual(updated.tracks[0].clips[0].duration.seconds, 1.5, accuracy: 0.0001)
        XCTAssertEqual(updated.tracks[0].clips[1].startTime.seconds, 1.5, accuracy: 0.0001)
        XCTAssertEqual(updated.tracks[0].clips[1].duration.seconds, 2.5, accuracy: 0.0001)
    }

    func testApplyIntent_rippleTrimOutShiftsDownstreamClips() async {
        let a = Clip(
            name: "A",
            asset: AssetReference(sourceFn: "ligm://video/smpte_bars"),
            startTime: Time(seconds: 0.0),
            duration: Time(seconds: 2.0)
        )
        let b = Clip(
            name: "B",
            asset: AssetReference(sourceFn: "ligm://video/macbeth"),
            startTime: Time(seconds: 2.0),
            duration: Time(seconds: 2.0)
        )
        let track = Track(name: "V", kind: .video, clips: [a, b])
        let timeline = Timeline(tracks: [track], duration: Time(seconds: 4.0))

        let session = ProjectSession(initialState: ProjectState(timeline: timeline), trace: NoOpTraceSink())
        // Ripple trim A from end=2.0 to end=3.0 => delta +1.0, so B shifts from 2.0 to 3.0.
        await session.applyIntent(UserIntent(action: .rippleTrimOut, target: "clip", params: ["end_seconds": 3.0], clipId: a.id))

        let updated = await session.state.timeline
        XCTAssertEqual(updated.tracks[0].clips.count, 2)
        XCTAssertEqual(updated.tracks[0].clips[0].duration.seconds, 3.0, accuracy: 0.0001)
        XCTAssertEqual(updated.tracks[0].clips[1].startTime.seconds, 3.0, accuracy: 0.0001)
        XCTAssertEqual(updated.duration.seconds, 5.0, accuracy: 0.0001)
    }

    func testApplyIntent_rippleTrimInByOffsetShiftsDownstreamClipsEarlier() async throws {
        // Clip A has 1s offset already; ripple trim-in to 1.5s should shorten by 0.5s and pull B earlier by 0.5s.
        let a = Clip(
            name: "A",
            asset: AssetReference(sourceFn: "ligm://video/smpte_bars"),
            startTime: Time(seconds: 0.0),
            duration: Time(seconds: 2.0),
            offset: Time(seconds: 1.0)
        )
        let b = Clip(
            name: "B",
            asset: AssetReference(sourceFn: "ligm://video/macbeth"),
            startTime: Time(seconds: 2.0),
            duration: Time(seconds: 2.0)
        )
        let track = Track(name: "V", kind: .video, clips: [a, b])
        let timeline = Timeline(tracks: [track], duration: Time(seconds: 4.0))

        let session = ProjectSession(initialState: ProjectState(timeline: timeline), trace: NoOpTraceSink())
        await session.applyIntent(UserIntent(action: .rippleTrimIn, target: "clip", params: ["offset_seconds": 1.5], clipId: a.id))

        let updated = await session.state.timeline
        XCTAssertEqual(updated.tracks[0].clips.count, 2)

        let updatedA = updated.tracks[0].clips.first(where: { $0.id == a.id })
        let updatedB = updated.tracks[0].clips.first(where: { $0.id == b.id })
        let ua = try XCTUnwrap(updatedA)
        let ub = try XCTUnwrap(updatedB)

        XCTAssertEqual(ua.offset.seconds, 1.5, accuracy: 0.0001)
        XCTAssertEqual(ua.duration.seconds, 1.5, accuracy: 0.0001)
        XCTAssertEqual(ub.startTime.seconds, 1.5, accuracy: 0.0001)
        XCTAssertEqual(updated.duration.seconds, 3.5, accuracy: 0.0001)
    }

    func testApplyIntent_rippleDeletePullsDownstreamClipsLeft() async throws {
        let a = Clip(
            name: "A",
            asset: AssetReference(sourceFn: "ligm://video/smpte_bars"),
            startTime: Time(seconds: 0.0),
            duration: Time(seconds: 2.0)
        )
        let b = Clip(
            name: "B",
            asset: AssetReference(sourceFn: "ligm://video/macbeth"),
            startTime: Time(seconds: 2.0),
            duration: Time(seconds: 2.0)
        )
        let c = Clip(
            name: "C",
            asset: AssetReference(sourceFn: "ligm://video/zone_plate?speed=1.0"),
            startTime: Time(seconds: 4.0),
            duration: Time(seconds: 1.0)
        )

        let track = Track(name: "V", kind: .video, clips: [a, b, c])
        let timeline = Timeline(tracks: [track], duration: Time(seconds: 5.0))
        let session = ProjectSession(initialState: ProjectState(timeline: timeline), trace: NoOpTraceSink())

        await session.applyIntent(UserIntent(action: .rippleDelete, target: "clip", params: [:], clipId: b.id))

        let updated = await session.state.timeline
        XCTAssertEqual(updated.tracks[0].clips.count, 2)

        let ua = try XCTUnwrap(updated.tracks[0].clips.first(where: { $0.id == a.id }))
        let uc = try XCTUnwrap(updated.tracks[0].clips.first(where: { $0.id == c.id }))
        XCTAssertEqual(ua.startTime.seconds, 0.0, accuracy: 0.0001)
        // C should move from 4.0 -> 2.0 (pulled left by B's 2.0s duration).
        XCTAssertEqual(uc.startTime.seconds, 2.0, accuracy: 0.0001)
        XCTAssertEqual(updated.duration.seconds, 3.0, accuracy: 0.0001)
    }
}
