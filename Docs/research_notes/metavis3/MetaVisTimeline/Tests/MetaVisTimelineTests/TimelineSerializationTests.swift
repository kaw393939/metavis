import XCTest
import MetaVisCore
@testable import MetaVisTimeline

final class TimelineSerializationTests: XCTestCase {
    
    func testFullTimelineSerialization() throws {
        // Create a complex timeline
        var timeline = Timeline(name: "Master Sequence")
        var track1 = Track(name: "Video")
        var track2 = Track(name: "Audio")
        
        let clip1 = Clip(
            name: "Shot 1",
            assetId: UUID(),
            range: TimeRange(start: .zero, duration: RationalTime(value: 24, timescale: 24)),
            sourceStartTime: .zero
        )
        try track1.add(clip1)
        
        let clip2 = Clip(
            name: "SFX 1",
            assetId: UUID(),
            range: TimeRange(start: RationalTime(value: 12, timescale: 24), duration: RationalTime(value: 12, timescale: 24)),
            sourceStartTime: .zero
        )
        try track2.add(clip2)
        
        timeline.addTrack(track1)
        timeline.addTrack(track2)
        
        // Encode
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(timeline)
        
        // Decode
        let decoder = JSONDecoder()
        let decodedTimeline = try decoder.decode(Timeline.self, from: data)
        
        // Verify
        XCTAssertEqual(decodedTimeline.name, "Master Sequence")
        XCTAssertEqual(decodedTimeline.tracks.count, 2)
        
        let decodedTrack1 = decodedTimeline.tracks[0]
        XCTAssertEqual(decodedTrack1.name, "Video")
        XCTAssertEqual(decodedTrack1.clips.count, 1)
        XCTAssertEqual(decodedTrack1.clips.first?.name, "Shot 1")
        
        let decodedTrack2 = decodedTimeline.tracks[1]
        XCTAssertEqual(decodedTrack2.name, "Audio")
        XCTAssertEqual(decodedTrack2.clips.count, 1)
        XCTAssertEqual(decodedTrack2.clips.first?.name, "SFX 1")
        
        // Verify deep structure (RationalTime)
        XCTAssertEqual(decodedTrack1.clips.first?.range.duration.value, 24)
    }
}
