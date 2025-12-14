import XCTest
import MetaVisCore
import MetaVisTimeline
import MetaVisServices
@testable import MetaVisSession

final class IntentToolsObservabilityTests: XCTestCase {

    func testApplyIntentMutatesTimelineAndEmitsTrace() async {
        let clip = Clip(
            name: "Clip",
            asset: AssetReference(sourceFn: "ligm://video/smpte_bars"),
            startTime: .zero,
            duration: Time(seconds: 2.0)
        )
        let track = Track(name: "V", kind: .video, clips: [clip])
        let timeline = Timeline(tracks: [track], duration: Time(seconds: 2.0))

        let trace = InMemoryTraceSink()
        let session = ProjectSession(initialState: ProjectState(timeline: timeline), trace: trace)

        let intent = UserIntent(action: .colorGrade, target: "clip", params: ["contrast": 1.1, "exposure": 0.2])
        await session.applyIntent(intent)

        let updated = await session.state
        let effects = updated.timeline.tracks[0].clips[0].effects
        let cg = effects.first(where: { $0.id == "mv.colorGrade" })
        XCTAssertNotNil(cg)
        XCTAssertEqual(cg?.parameters["target"], .string("clip"))
        XCTAssertEqual(cg?.parameters["exposure"], .float(0.2))
        XCTAssertEqual(cg?.parameters["contrast"], .float(1.1))

        let events = await trace.snapshot()
        let names = events.map { $0.name }

        XCTAssertTrue(names.contains("intent.apply.begin"))
        XCTAssertTrue(names.contains("intent.commands.built"))
        XCTAssertTrue(names.contains("intent.commands.execute.begin"))
        XCTAssertTrue(names.contains("intent.commands.execute.end"))
        XCTAssertTrue(names.contains("intent.apply.end"))

        // Deterministic ordering for the core flow.
        XCTAssertLessThan(names.firstIndex(of: "intent.apply.begin") ?? Int.max,
                         names.firstIndex(of: "intent.apply.end") ?? Int.min)
    }
}
