import XCTest
import MetaVisCore
import MetaVisTimeline
import MetaVisServices
@testable import MetaVisSession

final class IntentUndoRedoTests: XCTestCase {

    func testApplyIntentCanUndoAndRedoTimelineMutation() async {
        let clip = Clip(
            name: "Clip",
            asset: AssetReference(sourceFn: "ligm://video/smpte_bars"),
            startTime: .zero,
            duration: Time(seconds: 2.0)
        )
        let track = Track(name: "V", kind: .video, clips: [clip])
        let timeline = Timeline(tracks: [track], duration: Time(seconds: 2.0))

        let session = ProjectSession(initialState: ProjectState(timeline: timeline), trace: NoOpTraceSink())

        await session.applyIntent(UserIntent(action: .colorGrade, target: "clip", params: ["exposure": 0.3]))

        let afterApply = await session.state.timeline
        XCTAssertEqual(afterApply.tracks[0].clips[0].effects.first?.id, "mv.colorGrade")

        await session.undo()
        let afterUndo = await session.state.timeline
        XCTAssertTrue(afterUndo.tracks[0].clips[0].effects.isEmpty)

        await session.redo()
        let afterRedo = await session.state.timeline
        XCTAssertEqual(afterRedo.tracks[0].clips[0].effects.first?.id, "mv.colorGrade")
        XCTAssertEqual(afterRedo.tracks[0].clips[0].effects.first?.parameters["exposure"], .float(0.3))
    }
}
