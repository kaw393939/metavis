import XCTest
import MetaVisCore
import MetaVisTimeline
@testable import MetaVisSession

final class ProcessAndApplyCommandE2ETests: XCTestCase {

    func testProcessAndApplyCommand_targetsSecondVideoClipWhenRequested() async throws {
        let first = Clip(
            name: "First",
            asset: AssetReference(sourceFn: "ligm://video/smpte_bars"),
            startTime: Time(seconds: 0.0),
            duration: Time(seconds: 2.0)
        )
        let second = Clip(
            name: "Second",
            asset: AssetReference(sourceFn: "ligm://video/macbeth"),
            startTime: Time(seconds: 2.0),
            duration: Time(seconds: 2.0)
        )
        let track = Track(name: "V", kind: .video, clips: [first, second])
        let timeline = Timeline(tracks: [track], duration: Time(seconds: 4.0))

        let session = ProjectSession(initialState: ProjectState(timeline: timeline), trace: NoOpTraceSink())

        // The LocalLLMService mock uses the encoded editing context to pick the 2nd clip ID.
        _ = try await session.processAndApplyCommand("ripple trim out the second clip")

        let updated = await session.state.timeline
        XCTAssertEqual(updated.tracks[0].clips.count, 2)

        // Second clip should be the target: its duration should change from 2s to (end=3s => duration=1s).
        // The first clip should be unchanged.
        let updatedFirst = updated.tracks[0].clips.first(where: { $0.id == first.id })
        let updatedSecond = updated.tracks[0].clips.first(where: { $0.id == second.id })

        let f = try XCTUnwrap(updatedFirst)
        let s = try XCTUnwrap(updatedSecond)
        XCTAssertEqual(f.duration.seconds, 2.0, accuracy: 0.0001)
        XCTAssertEqual(s.duration.seconds, 1.0, accuracy: 0.0001)
    }

    func testProcessAndApplyCommand_rippleDeletesSecondClip() async throws {
        let first = Clip(
            name: "First",
            asset: AssetReference(sourceFn: "ligm://video/smpte_bars"),
            startTime: Time(seconds: 0.0),
            duration: Time(seconds: 2.0)
        )
        let second = Clip(
            name: "Second",
            asset: AssetReference(sourceFn: "ligm://video/macbeth"),
            startTime: Time(seconds: 2.0),
            duration: Time(seconds: 2.0)
        )
        let third = Clip(
            name: "Third",
            asset: AssetReference(sourceFn: "ligm://video/zone_plate?speed=1.0"),
            startTime: Time(seconds: 4.0),
            duration: Time(seconds: 1.0)
        )
        let track = Track(name: "V", kind: .video, clips: [first, second, third])
        let timeline = Timeline(tracks: [track], duration: Time(seconds: 5.0))

        let session = ProjectSession(initialState: ProjectState(timeline: timeline), trace: NoOpTraceSink())

        _ = try await session.processAndApplyCommand("ripple delete the second clip")

        let updated = await session.state.timeline
        XCTAssertEqual(updated.tracks[0].clips.count, 2)

        // Third clip should pull left by 2 seconds (duration of deleted second clip).
        let updatedThird = try XCTUnwrap(updated.tracks[0].clips.first(where: { $0.id == third.id }))
        XCTAssertEqual(updatedThird.startTime.seconds, 2.0, accuracy: 0.0001)
        XCTAssertEqual(updated.duration.seconds, 3.0, accuracy: 0.0001)
    }

    func testProcessAndApplyCommand_rippleDeleteByNameTokenTargetsMatchingClip() async throws {
        let smpte = Clip(
            name: "SMPTE",
            asset: AssetReference(sourceFn: "ligm://video/smpte_bars"),
            startTime: Time(seconds: 0.0),
            duration: Time(seconds: 2.0)
        )
        let macbeth = Clip(
            name: "Macbeth",
            asset: AssetReference(sourceFn: "ligm://video/macbeth"),
            startTime: Time(seconds: 2.0),
            duration: Time(seconds: 2.0)
        )
        let zone = Clip(
            name: "Zone",
            asset: AssetReference(sourceFn: "ligm://video/zone_plate?speed=1.0"),
            startTime: Time(seconds: 4.0),
            duration: Time(seconds: 1.0)
        )
        let track = Track(name: "V", kind: .video, clips: [smpte, macbeth, zone])
        let timeline = Timeline(tracks: [track], duration: Time(seconds: 5.0))

        let session = ProjectSession(initialState: ProjectState(timeline: timeline), trace: NoOpTraceSink())
        _ = try await session.processAndApplyCommand("ripple delete macbeth")

        let updated = await session.state.timeline
        XCTAssertEqual(updated.tracks[0].clips.count, 2)
        XCTAssertNil(updated.tracks[0].clips.first(where: { $0.id == macbeth.id }))

        // Zone clip should pull left by 2 seconds.
        let updatedZone = try XCTUnwrap(updated.tracks[0].clips.first(where: { $0.id == zone.id }))
        XCTAssertEqual(updatedZone.startTime.seconds, 2.0, accuracy: 0.0001)
        XCTAssertEqual(updated.duration.seconds, 3.0, accuracy: 0.0001)
    }

    func testProcessAndApplyCommand_moveByNameParsesStartSeconds() async throws {
        let smpte = Clip(
            name: "SMPTE",
            asset: AssetReference(sourceFn: "ligm://video/smpte_bars"),
            startTime: Time(seconds: 0.0),
            duration: Time(seconds: 2.0)
        )
        let macbeth = Clip(
            name: "Macbeth",
            asset: AssetReference(sourceFn: "ligm://video/macbeth"),
            startTime: Time(seconds: 2.0),
            duration: Time(seconds: 2.0)
        )
        let zone = Clip(
            name: "Zone",
            asset: AssetReference(sourceFn: "ligm://video/zone_plate?speed=1.0"),
            startTime: Time(seconds: 4.0),
            duration: Time(seconds: 1.0)
        )
        let track = Track(name: "V", kind: .video, clips: [smpte, macbeth, zone])
        let timeline = Timeline(tracks: [track], duration: Time(seconds: 5.0))

        let session = ProjectSession(initialState: ProjectState(timeline: timeline), trace: NoOpTraceSink())
        _ = try await session.processAndApplyCommand("move macbeth to 1.25s")

        let updated = await session.state.timeline
        let moved = try XCTUnwrap(updated.tracks[0].clips.first(where: { $0.id == macbeth.id }))
        XCTAssertEqual(moved.startTime.seconds, 1.25, accuracy: 0.0001)
    }

    func testProcessAndApplyCommand_moveByNameParsesDeltaSeconds() async throws {
        let smpte = Clip(
            name: "SMPTE",
            asset: AssetReference(sourceFn: "ligm://video/smpte_bars"),
            startTime: Time(seconds: 0.0),
            duration: Time(seconds: 2.0)
        )
        let macbeth = Clip(
            name: "Macbeth",
            asset: AssetReference(sourceFn: "ligm://video/macbeth"),
            startTime: Time(seconds: 2.0),
            duration: Time(seconds: 2.0)
        )
        let zone = Clip(
            name: "Zone",
            asset: AssetReference(sourceFn: "ligm://video/zone_plate?speed=1.0"),
            startTime: Time(seconds: 4.0),
            duration: Time(seconds: 1.0)
        )
        let track = Track(name: "V", kind: .video, clips: [smpte, macbeth, zone])
        let timeline = Timeline(tracks: [track], duration: Time(seconds: 5.0))

        let session = ProjectSession(initialState: ProjectState(timeline: timeline), trace: NoOpTraceSink())
        _ = try await session.processAndApplyCommand("move macbeth by -0.5s")

        let updated = await session.state.timeline
        let moved = try XCTUnwrap(updated.tracks[0].clips.first(where: { $0.id == macbeth.id }))
        XCTAssertEqual(moved.startTime.seconds, 1.5, accuracy: 0.0001)
    }

    func testProcessAndApplyCommand_rippleTrimInByNameParsesOffsetSeconds() async throws {
        let smpte = Clip(
            name: "SMPTE",
            asset: AssetReference(sourceFn: "ligm://video/smpte_bars"),
            startTime: Time(seconds: 0.0),
            duration: Time(seconds: 2.0)
        )
        let macbeth = Clip(
            name: "Macbeth",
            asset: AssetReference(sourceFn: "ligm://video/macbeth"),
            startTime: Time(seconds: 2.0),
            duration: Time(seconds: 2.0),
            offset: Time(seconds: 0.0)
        )
        let zone = Clip(
            name: "Zone",
            asset: AssetReference(sourceFn: "ligm://video/zone_plate?speed=1.0"),
            startTime: Time(seconds: 4.0),
            duration: Time(seconds: 1.0)
        )
        let track = Track(name: "V", kind: .video, clips: [smpte, macbeth, zone])
        let timeline = Timeline(tracks: [track], duration: Time(seconds: 5.0))

        let session = ProjectSession(initialState: ProjectState(timeline: timeline), trace: NoOpTraceSink())
        _ = try await session.processAndApplyCommand("ripple trim in macbeth to 0.5s")

        let updated = await session.state.timeline
        let trimmed = try XCTUnwrap(updated.tracks[0].clips.first(where: { $0.id == macbeth.id }))
        XCTAssertEqual(trimmed.offset.seconds, 0.5, accuracy: 0.0001)
        XCTAssertEqual(trimmed.duration.seconds, 1.5, accuracy: 0.0001)

        let shiftedZone = try XCTUnwrap(updated.tracks[0].clips.first(where: { $0.id == zone.id }))
        XCTAssertEqual(shiftedZone.startTime.seconds, 3.5, accuracy: 0.0001)
    }

    func testProcessAndApplyCommand_rippleTrimInByNameParsesDeltaSeconds() async throws {
        let smpte = Clip(
            name: "SMPTE",
            asset: AssetReference(sourceFn: "ligm://video/smpte_bars"),
            startTime: Time(seconds: 0.0),
            duration: Time(seconds: 2.0)
        )
        let macbeth = Clip(
            name: "Macbeth",
            asset: AssetReference(sourceFn: "ligm://video/macbeth"),
            startTime: Time(seconds: 2.0),
            duration: Time(seconds: 2.0),
            offset: Time(seconds: 0.25)
        )
        let zone = Clip(
            name: "Zone",
            asset: AssetReference(sourceFn: "ligm://video/zone_plate?speed=1.0"),
            startTime: Time(seconds: 4.0),
            duration: Time(seconds: 1.0)
        )
        let track = Track(name: "V", kind: .video, clips: [smpte, macbeth, zone])
        let timeline = Timeline(tracks: [track], duration: Time(seconds: 5.0))

        let session = ProjectSession(initialState: ProjectState(timeline: timeline), trace: NoOpTraceSink())
        _ = try await session.processAndApplyCommand("ripple trim in macbeth by 0.5s")

        let updated = await session.state.timeline
        let trimmed = try XCTUnwrap(updated.tracks[0].clips.first(where: { $0.id == macbeth.id }))
        XCTAssertEqual(trimmed.offset.seconds, 0.75, accuracy: 0.0001)
        XCTAssertEqual(trimmed.duration.seconds, 1.5, accuracy: 0.0001)

        let shiftedZone = try XCTUnwrap(updated.tracks[0].clips.first(where: { $0.id == zone.id }))
        XCTAssertEqual(shiftedZone.startTime.seconds, 3.5, accuracy: 0.0001)
        XCTAssertEqual(updated.duration.seconds, 4.5, accuracy: 0.0001)
    }

    func testProcessAndApplyCommand_trimInByNameParsesDeltaSeconds() async throws {
        let smpte = Clip(
            name: "SMPTE",
            asset: AssetReference(sourceFn: "ligm://video/smpte_bars"),
            startTime: Time(seconds: 0.0),
            duration: Time(seconds: 2.0)
        )
        let macbeth = Clip(
            name: "Macbeth",
            asset: AssetReference(sourceFn: "ligm://video/macbeth"),
            startTime: Time(seconds: 2.0),
            duration: Time(seconds: 2.0),
            offset: Time(seconds: 0.25)
        )
        let zone = Clip(
            name: "Zone",
            asset: AssetReference(sourceFn: "ligm://video/zone_plate?speed=1.0"),
            startTime: Time(seconds: 4.0),
            duration: Time(seconds: 1.0)
        )
        let track = Track(name: "V", kind: .video, clips: [smpte, macbeth, zone])
        let timeline = Timeline(tracks: [track], duration: Time(seconds: 5.0))

        let session = ProjectSession(initialState: ProjectState(timeline: timeline), trace: NoOpTraceSink())
        _ = try await session.processAndApplyCommand("trim in macbeth by 0.5s")

        let updated = await session.state.timeline
        let trimmed = try XCTUnwrap(updated.tracks[0].clips.first(where: { $0.id == macbeth.id }))
        XCTAssertEqual(trimmed.offset.seconds, 0.75, accuracy: 0.0001)
        // Non-ripple trim-in should not move downstream clips.
        let updatedZone = try XCTUnwrap(updated.tracks[0].clips.first(where: { $0.id == zone.id }))
        XCTAssertEqual(updatedZone.startTime.seconds, 4.0, accuracy: 0.0001)
    }

    func testProcessAndApplyCommand_rippleIsTrackOnly_audioUnaffected() async throws {
        let v1 = Clip(
            name: "SMPTE",
            asset: AssetReference(sourceFn: "ligm://video/smpte_bars"),
            startTime: Time(seconds: 0.0),
            duration: Time(seconds: 2.0)
        )
        let v2 = Clip(
            name: "Macbeth",
            asset: AssetReference(sourceFn: "ligm://video/macbeth"),
            startTime: Time(seconds: 2.0),
            duration: Time(seconds: 2.0)
        )
        let v3 = Clip(
            name: "Zone",
            asset: AssetReference(sourceFn: "ligm://video/zone_plate?speed=1.0"),
            startTime: Time(seconds: 4.0),
            duration: Time(seconds: 1.0)
        )
        let video = Track(name: "V", kind: .video, clips: [v1, v2, v3])

        let a1 = Clip(
            name: "A-SMPTE",
            asset: AssetReference(sourceFn: "ligm://audio/tone?hz=440"),
            startTime: Time(seconds: 0.0),
            duration: Time(seconds: 5.0)
        )
        let audio = Track(name: "A", kind: .audio, clips: [a1])

        let timeline = Timeline(tracks: [video, audio], duration: Time(seconds: 5.0))
        let session = ProjectSession(initialState: ProjectState(timeline: timeline), trace: NoOpTraceSink())

        _ = try await session.processAndApplyCommand("ripple delete macbeth")

        let updated = await session.state.timeline
        let updatedAudio = try XCTUnwrap(updated.tracks.first(where: { $0.kind == .audio }))
        XCTAssertEqual(updatedAudio.clips.count, 1)
        XCTAssertEqual(updatedAudio.clips[0].startTime.seconds, 0.0, accuracy: 0.0001)
        XCTAssertEqual(updatedAudio.clips[0].duration.seconds, 5.0, accuracy: 0.0001)
    }

    func testProcessAndApplyCommand_trimEndByNameParsesEndSeconds() async throws {
        let smpte = Clip(
            name: "SMPTE",
            asset: AssetReference(sourceFn: "ligm://video/smpte_bars"),
            startTime: Time(seconds: 0.0),
            duration: Time(seconds: 2.0)
        )
        let macbeth = Clip(
            name: "Macbeth",
            asset: AssetReference(sourceFn: "ligm://video/macbeth"),
            startTime: Time(seconds: 2.0),
            duration: Time(seconds: 2.0)
        )
        let zone = Clip(
            name: "Zone",
            asset: AssetReference(sourceFn: "ligm://video/zone_plate?speed=1.0"),
            startTime: Time(seconds: 4.0),
            duration: Time(seconds: 1.0)
        )
        let track = Track(name: "V", kind: .video, clips: [smpte, macbeth, zone])
        let timeline = Timeline(tracks: [track], duration: Time(seconds: 5.0))

        let session = ProjectSession(initialState: ProjectState(timeline: timeline), trace: NoOpTraceSink())
        _ = try await session.processAndApplyCommand("trim macbeth to 3.25s")

        let updated = await session.state.timeline
        let trimmed = try XCTUnwrap(updated.tracks[0].clips.first(where: { $0.id == macbeth.id }))
        XCTAssertEqual(trimmed.duration.seconds, 1.25, accuracy: 0.0001)
        // Non-ripple trim doesn't move downstream clips.
        let updatedZone = try XCTUnwrap(updated.tracks[0].clips.first(where: { $0.id == zone.id }))
        XCTAssertEqual(updatedZone.startTime.seconds, 4.0, accuracy: 0.0001)
        XCTAssertEqual(updated.duration.seconds, 5.0, accuracy: 0.0001)
    }

    func testProcessAndApplyCommand_rippleTrimOutByNameParsesEndSecondsAndRipplesDownstream() async throws {
        let smpte = Clip(
            name: "SMPTE",
            asset: AssetReference(sourceFn: "ligm://video/smpte_bars"),
            startTime: Time(seconds: 0.0),
            duration: Time(seconds: 2.0)
        )
        let macbeth = Clip(
            name: "Macbeth",
            asset: AssetReference(sourceFn: "ligm://video/macbeth"),
            startTime: Time(seconds: 2.0),
            duration: Time(seconds: 2.0)
        )
        let zone = Clip(
            name: "Zone",
            asset: AssetReference(sourceFn: "ligm://video/zone_plate?speed=1.0"),
            startTime: Time(seconds: 4.0),
            duration: Time(seconds: 1.0)
        )
        let track = Track(name: "V", kind: .video, clips: [smpte, macbeth, zone])
        let timeline = Timeline(tracks: [track], duration: Time(seconds: 5.0))

        let session = ProjectSession(initialState: ProjectState(timeline: timeline), trace: NoOpTraceSink())
        _ = try await session.processAndApplyCommand("ripple trim out macbeth to 3.25s")

        let updated = await session.state.timeline
        let trimmed = try XCTUnwrap(updated.tracks[0].clips.first(where: { $0.id == macbeth.id }))
        XCTAssertEqual(trimmed.duration.seconds, 1.25, accuracy: 0.0001)

        // Downstream clip pulls left by 0.75s (oldEnd=4.0 -> newEnd=3.25).
        let shiftedZone = try XCTUnwrap(updated.tracks[0].clips.first(where: { $0.id == zone.id }))
        XCTAssertEqual(shiftedZone.startTime.seconds, 3.25, accuracy: 0.0001)
        XCTAssertEqual(updated.duration.seconds, 4.25, accuracy: 0.0001)
    }

    func testProcessAndApplyCommand_rippleTrimOutByNameParsesDeltaSecondsAndRipplesDownstream() async throws {
        let smpte = Clip(
            name: "SMPTE",
            asset: AssetReference(sourceFn: "ligm://video/smpte_bars"),
            startTime: Time(seconds: 0.0),
            duration: Time(seconds: 2.0)
        )
        let macbeth = Clip(
            name: "Macbeth",
            asset: AssetReference(sourceFn: "ligm://video/macbeth"),
            startTime: Time(seconds: 2.0),
            duration: Time(seconds: 2.0)
        )
        let zone = Clip(
            name: "Zone",
            asset: AssetReference(sourceFn: "ligm://video/zone_plate?speed=1.0"),
            startTime: Time(seconds: 4.0),
            duration: Time(seconds: 1.0)
        )
        let track = Track(name: "V", kind: .video, clips: [smpte, macbeth, zone])
        let timeline = Timeline(tracks: [track], duration: Time(seconds: 5.0))

        let session = ProjectSession(initialState: ProjectState(timeline: timeline), trace: NoOpTraceSink())
        _ = try await session.processAndApplyCommand("ripple trim out macbeth by 0.5s")

        let updated = await session.state.timeline
        let trimmed = try XCTUnwrap(updated.tracks[0].clips.first(where: { $0.id == macbeth.id }))
        XCTAssertEqual(trimmed.duration.seconds, 1.5, accuracy: 0.0001)

        let shiftedZone = try XCTUnwrap(updated.tracks[0].clips.first(where: { $0.id == zone.id }))
        XCTAssertEqual(shiftedZone.startTime.seconds, 3.5, accuracy: 0.0001)
        XCTAssertEqual(updated.duration.seconds, 4.5, accuracy: 0.0001)
    }

    func testProcessAndApplyCommand_speedByNameParsesFactor() async throws {
        let smpte = Clip(
            name: "SMPTE",
            asset: AssetReference(sourceFn: "ligm://video/smpte_bars"),
            startTime: Time(seconds: 0.0),
            duration: Time(seconds: 2.0)
        )
        let macbeth = Clip(
            name: "Macbeth",
            asset: AssetReference(sourceFn: "ligm://video/macbeth"),
            startTime: Time(seconds: 2.0),
            duration: Time(seconds: 2.0)
        )
        let track = Track(name: "V", kind: .video, clips: [smpte, macbeth])
        let timeline = Timeline(tracks: [track], duration: Time(seconds: 4.0))

        let session = ProjectSession(initialState: ProjectState(timeline: timeline), trace: NoOpTraceSink())
        _ = try await session.processAndApplyCommand("speed macbeth 1.5")

        let updated = await session.state.timeline
        let updatedMacbeth = try XCTUnwrap(updated.tracks[0].clips.first(where: { $0.id == macbeth.id }))
        let retime = try XCTUnwrap(updatedMacbeth.effects.first(where: { $0.id == "mv.retime" }))
        XCTAssertEqual(retime.parameters["factor"], .float(1.5))
    }

    func testProcessAndApplyCommand_cutByNameParsesTimeAndBladesClip() async throws {
        let smpte = Clip(
            name: "SMPTE",
            asset: AssetReference(sourceFn: "ligm://video/smpte_bars"),
            startTime: Time(seconds: 0.0),
            duration: Time(seconds: 2.0)
        )

        var macbeth = Clip(
            name: "Macbeth",
            asset: AssetReference(sourceFn: "ligm://video/macbeth"),
            startTime: Time(seconds: 2.0),
            duration: Time(seconds: 4.0),
            offset: Time(seconds: 1.0)
        )
        macbeth.transitionIn = .crossfade(duration: Time(seconds: 0.5))
        macbeth.transitionOut = .crossfade(duration: Time(seconds: 0.5))

        let zone = Clip(
            name: "Zone",
            asset: AssetReference(sourceFn: "ligm://video/zone_plate?speed=1.0"),
            startTime: Time(seconds: 6.0),
            duration: Time(seconds: 1.0)
        )
        let track = Track(name: "V", kind: .video, clips: [smpte, macbeth, zone])
        let timeline = Timeline(tracks: [track], duration: Time(seconds: 7.0))

        let session = ProjectSession(initialState: ProjectState(timeline: timeline), trace: NoOpTraceSink())
        _ = try await session.processAndApplyCommand("cut macbeth at 4.5s")

        let updated = await session.state.timeline
        XCTAssertEqual(updated.tracks[0].clips.count, 4)

        let first = try XCTUnwrap(updated.tracks[0].clips.first(where: { abs($0.startTime.seconds - 2.0) < 0.0001 }))
        let second = try XCTUnwrap(updated.tracks[0].clips.first(where: { abs($0.startTime.seconds - 4.5) < 0.0001 }))

        XCTAssertEqual(first.duration.seconds, 2.5, accuracy: 0.0001)
        XCTAssertEqual(first.offset.seconds, 1.0, accuracy: 0.0001)
        XCTAssertNotNil(first.transitionIn)
        XCTAssertNil(first.transitionOut)

        XCTAssertEqual(second.duration.seconds, 1.5, accuracy: 0.0001)
        XCTAssertEqual(second.offset.seconds, 3.5, accuracy: 0.0001)
        XCTAssertNil(second.transitionIn)
        XCTAssertNotNil(second.transitionOut)
    }

    func testProcessAndApplyCommand_rippleTrimOutByNameShortenShiftsOverlappedNextClip() async throws {
        let fade = Transition.crossfade(duration: Time(seconds: 0.5))

        let smpte = Clip(
            name: "SMPTE",
            asset: AssetReference(sourceFn: "ligm://video/smpte_bars"),
            startTime: Time(seconds: 0.0),
            duration: Time(seconds: 2.0)
        )

        var macbeth = Clip(
            name: "Macbeth",
            asset: AssetReference(sourceFn: "ligm://video/macbeth"),
            startTime: Time(seconds: 2.0),
            duration: Time(seconds: 3.0)
        )
        macbeth.transitionOut = fade

        var zone = Clip(
            name: "Zone",
            asset: AssetReference(sourceFn: "ligm://video/zone_plate?speed=1.0"),
            startTime: Time(seconds: 4.5), // overlaps Macbeth end (5.0) by 0.5s
            duration: Time(seconds: 1.0)
        )
        zone.transitionIn = fade

        let track = Track(name: "V", kind: .video, clips: [smpte, macbeth, zone])
        let timeline = Timeline(tracks: [track], duration: Time(seconds: 5.5))

        let session = ProjectSession(initialState: ProjectState(timeline: timeline), trace: NoOpTraceSink())
        _ = try await session.processAndApplyCommand("ripple trim out macbeth by 1s")

        let updated = await session.state.timeline
        let updatedMacbeth = try XCTUnwrap(updated.tracks[0].clips.first(where: { $0.id == macbeth.id }))
        let updatedZone = try XCTUnwrap(updated.tracks[0].clips.first(where: { $0.id == zone.id }))

        // Macbeth end moved earlier by 1s: 5.0 -> 4.0.
        // Zone should shift earlier by the same amount even though it overlapped the old end.
        XCTAssertEqual(updatedMacbeth.endTime.seconds, 4.0, accuracy: 0.0001)
        XCTAssertEqual(updatedZone.startTime.seconds, 3.5, accuracy: 0.0001)

        // Paired transitions remain valid (<= overlap) after the edit.
        let out = try XCTUnwrap(updatedMacbeth.transitionOut)
        let `in` = try XCTUnwrap(updatedZone.transitionIn)
        XCTAssertEqual(out.duration.seconds, 0.5, accuracy: 0.0001)
        XCTAssertEqual(`in`.duration.seconds, 0.5, accuracy: 0.0001)
    }

    func testProcessAndApplyCommand_rippleTrimInByNameShortenShiftsOverlappedNextClip() async throws {
        let fade = Transition.crossfade(duration: Time(seconds: 0.5))

        let smpte = Clip(
            name: "SMPTE",
            asset: AssetReference(sourceFn: "ligm://video/smpte_bars"),
            startTime: Time(seconds: 0.0),
            duration: Time(seconds: 2.0)
        )

        var macbeth = Clip(
            name: "Macbeth",
            asset: AssetReference(sourceFn: "ligm://video/macbeth"),
            startTime: Time(seconds: 2.0),
            duration: Time(seconds: 3.0),
            offset: .zero
        )
        macbeth.transitionOut = fade

        var zone = Clip(
            name: "Zone",
            asset: AssetReference(sourceFn: "ligm://video/zone_plate?speed=1.0"),
            startTime: Time(seconds: 4.5), // overlaps Macbeth end (5.0) by 0.5s
            duration: Time(seconds: 1.0)
        )
        zone.transitionIn = fade

        let track = Track(name: "V", kind: .video, clips: [smpte, macbeth, zone])
        let timeline = Timeline(tracks: [track], duration: Time(seconds: 5.5))

        let session = ProjectSession(initialState: ProjectState(timeline: timeline), trace: NoOpTraceSink())
        _ = try await session.processAndApplyCommand("ripple trim in macbeth by 1s")

        let updated = await session.state.timeline
        let updatedMacbeth = try XCTUnwrap(updated.tracks[0].clips.first(where: { $0.id == macbeth.id }))
        let updatedZone = try XCTUnwrap(updated.tracks[0].clips.first(where: { $0.id == zone.id }))

        // Ripple trim-in by +1s reduces duration by 1s:
        // end moved earlier by 1s: 5.0 -> 4.0.
        // Zone should shift earlier by the same amount even though it overlapped the old end.
        XCTAssertEqual(updatedMacbeth.endTime.seconds, 4.0, accuracy: 0.0001)
        XCTAssertEqual(updatedZone.startTime.seconds, 3.5, accuracy: 0.0001)

        // Paired transitions remain valid (<= overlap) after the edit.
        let out = try XCTUnwrap(updatedMacbeth.transitionOut)
        let `in` = try XCTUnwrap(updatedZone.transitionIn)
        XCTAssertEqual(out.duration.seconds, 0.5, accuracy: 0.0001)
        XCTAssertEqual(`in`.duration.seconds, 0.5, accuracy: 0.0001)
    }

    func testProcessAndApplyCommand_rippleDeleteByNameShiftsOverlappedDownstreamClip() async throws {
        let fade = Transition.crossfade(duration: Time(seconds: 0.5))

        var smpte = Clip(
            name: "SMPTE",
            asset: AssetReference(sourceFn: "ligm://video/smpte_bars"),
            startTime: Time(seconds: 0.0),
            duration: Time(seconds: 2.0)
        )
        smpte.transitionOut = fade

        var macbeth = Clip(
            name: "Macbeth",
            asset: AssetReference(sourceFn: "ligm://video/macbeth"),
            startTime: Time(seconds: 2.0),
            duration: Time(seconds: 3.0)
        )
        macbeth.transitionIn = fade
        macbeth.transitionOut = fade

        var zone = Clip(
            name: "Zone",
            asset: AssetReference(sourceFn: "ligm://video/zone_plate?speed=1.0"),
            startTime: Time(seconds: 4.5), // overlaps Macbeth end (5.0) by 0.5s
            duration: Time(seconds: 1.0)
        )
        zone.transitionIn = fade

        let track = Track(name: "V", kind: .video, clips: [smpte, macbeth, zone])
        let timeline = Timeline(tracks: [track], duration: Time(seconds: 5.5))

        let session = ProjectSession(initialState: ProjectState(timeline: timeline), trace: NoOpTraceSink())
        _ = try await session.processAndApplyCommand("ripple delete macbeth")

        let updated = await session.state.timeline
        XCTAssertNil(updated.tracks[0].clips.first(where: { $0.id == macbeth.id }))

        let updatedSMPTE = try XCTUnwrap(updated.tracks[0].clips.first(where: { $0.id == smpte.id }))
        let updatedZone = try XCTUnwrap(updated.tracks[0].clips.first(where: { $0.id == zone.id }))

        // Zone must shift earlier by -Macbeth.duration (3s) even though it started before Macbeth's end.
        XCTAssertEqual(updatedZone.startTime.seconds, 1.5, accuracy: 0.0001)

        // Deleting Macbeth should not leave SMPTE.fadeOut / Zone.fadeIn attached to a now-different boundary.
        XCTAssertNil(updatedSMPTE.transitionOut)
        XCTAssertNil(updatedZone.transitionIn)
    }
}
