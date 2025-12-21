import XCTest
import MetaVisCore
import MetaVisTimeline
@testable import MetaVisSession

final class BatchedCommandUndoRedoE2ETests: XCTestCase {

    func testProcessAndApplyCommandThenIsAtomicForUndoRedo() async throws {
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

        _ = try await session.processAndApplyCommand("move macbeth to 1s then ripple delete zone")

        let after = await session.state.timeline
        let afterMacbeth = try XCTUnwrap(after.tracks[0].clips.first(where: { $0.id == macbeth.id }))
        XCTAssertEqual(afterMacbeth.startTime.seconds, 1.0, accuracy: 0.0001)
        XCTAssertNil(after.tracks[0].clips.first(where: { $0.id == zone.id }))

        // One undo should revert both edits.
        await session.undo()
        let afterUndo = await session.state.timeline
        let undoMacbeth = try XCTUnwrap(afterUndo.tracks[0].clips.first(where: { $0.id == macbeth.id }))
        let undoZone = try XCTUnwrap(afterUndo.tracks[0].clips.first(where: { $0.id == zone.id }))
        XCTAssertEqual(undoMacbeth.startTime.seconds, 2.0, accuracy: 0.0001)
        XCTAssertEqual(undoZone.startTime.seconds, 4.0, accuracy: 0.0001)

        // One redo should re-apply both edits.
        await session.redo()
        let afterRedo = await session.state.timeline
        let redoMacbeth = try XCTUnwrap(afterRedo.tracks[0].clips.first(where: { $0.id == macbeth.id }))
        XCTAssertEqual(redoMacbeth.startTime.seconds, 1.0, accuracy: 0.0001)
        XCTAssertNil(afterRedo.tracks[0].clips.first(where: { $0.id == zone.id }))
    }

    func testProcessAndApplyCommandThenWhenSecondClauseFailsStillAllowsSingleUndoRedo() async throws {
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

        // Second clause is intentionally unparseable by the mock LLM/intent parser.
        _ = try await session.processAndApplyCommand("move macbeth to 1s then blargle flargle")

        let after = await session.state.timeline
        let afterMacbeth = try XCTUnwrap(after.tracks[0].clips.first(where: { $0.id == macbeth.id }))
        XCTAssertEqual(afterMacbeth.startTime.seconds, 1.0, accuracy: 0.0001)

        // One undo should revert the successful clause.
        await session.undo()
        let afterUndo = await session.state.timeline
        let undoMacbeth = try XCTUnwrap(afterUndo.tracks[0].clips.first(where: { $0.id == macbeth.id }))
        XCTAssertEqual(undoMacbeth.startTime.seconds, 2.0, accuracy: 0.0001)

        // One redo should re-apply the successful clause.
        await session.redo()
        let afterRedo = await session.state.timeline
        let redoMacbeth = try XCTUnwrap(afterRedo.tracks[0].clips.first(where: { $0.id == macbeth.id }))
        XCTAssertEqual(redoMacbeth.startTime.seconds, 1.0, accuracy: 0.0001)
    }
}
