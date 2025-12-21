import XCTest
import MetaVisCore
@testable import MetaVisTimeline

final class TimelineResolverTests: XCTestCase {
    
    func testSimpleSequence() throws {
        var timeline = Timeline(name: "Sequence")
        var track = Track(name: "V1")
        
        let clip1 = Clip(
            name: "A",
            assetId: UUID(),
            range: TimeRange(start: .zero, duration: RationalTime(value: 10, timescale: 1)),
            sourceStartTime: .zero
        )
        
        let clip2 = Clip(
            name: "B",
            assetId: UUID(),
            range: TimeRange(start: RationalTime(value: 10, timescale: 1), duration: RationalTime(value: 10, timescale: 1)),
            sourceStartTime: .zero
        )
        
        try track.add(clip1)
        try track.add(clip2)
        timeline.addTrack(track)
        
        let resolver = TimelineResolver()
        let segments = resolver.resolve(timeline: timeline)
        
        XCTAssertEqual(segments.count, 2)
        
        XCTAssertEqual(segments[0].range.start, .zero)
        XCTAssertEqual(segments[0].range.duration, RationalTime(value: 10, timescale: 1))
        XCTAssertEqual(segments[0].activeClips.count, 1)
        XCTAssertEqual(segments[0].activeClips.first?.assetId, clip1.assetId)
        
        XCTAssertEqual(segments[1].range.start, RationalTime(value: 10, timescale: 1))
        XCTAssertEqual(segments[1].range.duration, RationalTime(value: 10, timescale: 1))
        XCTAssertEqual(segments[1].activeClips.count, 1)
        XCTAssertEqual(segments[1].activeClips.first?.assetId, clip2.assetId)
    }
    
    func testOverlap() throws {
        var timeline = Timeline(name: "Overlap")
        var track1 = Track(name: "V1")
        var track2 = Track(name: "V2")
        
        // Clip A: 0-10
        let clipA = Clip(
            name: "A",
            assetId: UUID(),
            range: TimeRange(start: .zero, duration: RationalTime(value: 10, timescale: 1)),
            sourceStartTime: .zero
        )
        try track1.add(clipA)
        
        // Clip B: 5-15
        let clipB = Clip(
            name: "B",
            assetId: UUID(),
            range: TimeRange(start: RationalTime(value: 5, timescale: 1), duration: RationalTime(value: 10, timescale: 1)),
            sourceStartTime: .zero
        )
        try track2.add(clipB)
        
        timeline.addTrack(track1)
        timeline.addTrack(track2)
        
        let resolver = TimelineResolver()
        let segments = resolver.resolve(timeline: timeline)
        
        // Expected Segments:
        // 1. 0-5: [A]
        // 2. 5-10: [A, B]
        // 3. 10-15: [B]
        
        XCTAssertEqual(segments.count, 3)
        
        // Segment 1
        XCTAssertEqual(segments[0].range.start, .zero)
        XCTAssertEqual(segments[0].range.duration, RationalTime(value: 5, timescale: 1))
        XCTAssertEqual(segments[0].activeClips.count, 1)
        XCTAssertEqual(segments[0].activeClips[0].assetId, clipA.assetId)
        
        // Segment 2
        XCTAssertEqual(segments[1].range.start, RationalTime(value: 5, timescale: 1))
        XCTAssertEqual(segments[1].range.duration, RationalTime(value: 5, timescale: 1))
        XCTAssertEqual(segments[1].activeClips.count, 2)
        // Order depends on track order in timeline.tracks
        XCTAssertEqual(segments[1].activeClips[0].assetId, clipA.assetId)
        XCTAssertEqual(segments[1].activeClips[1].assetId, clipB.assetId)
        
        // Segment 3
        XCTAssertEqual(segments[2].range.start, RationalTime(value: 10, timescale: 1))
        XCTAssertEqual(segments[2].range.duration, RationalTime(value: 5, timescale: 1))
        XCTAssertEqual(segments[2].activeClips.count, 1)
        XCTAssertEqual(segments[2].activeClips[0].assetId, clipB.assetId)
    }
    
    func testSourceTimeResolution() throws {
        var timeline = Timeline(name: "Source Time")
        var track = Track(name: "V1")
        
        // Clip: Timeline 10-20, Source 100-110
        let clip = Clip(
            name: "A",
            assetId: UUID(),
            range: TimeRange(start: RationalTime(value: 10, timescale: 1), duration: RationalTime(value: 10, timescale: 1)),
            sourceStartTime: RationalTime(value: 100, timescale: 1)
        )
        try track.add(clip)
        timeline.addTrack(track)
        
        // Add another clip on track 2 to split the first one
        // Clip B: Timeline 15-25
        var track2 = Track(name: "V2")
        let clipB = Clip(
            name: "B",
            assetId: UUID(),
            range: TimeRange(start: RationalTime(value: 15, timescale: 1), duration: RationalTime(value: 10, timescale: 1)),
            sourceStartTime: .zero
        )
        try track2.add(clipB)
        timeline.addTrack(track2)
        
        let resolver = TimelineResolver()
        let segments = resolver.resolve(timeline: timeline)
        
        // Segments:
        // 1. 10-15: [A]
        // 2. 15-20: [A, B]
        // 3. 20-25: [B]
        
        XCTAssertEqual(segments.count, 3)
        
        // Check Segment 2 (15-20)
        let seg2 = segments[1]
        XCTAssertEqual(seg2.range.start, RationalTime(value: 15, timescale: 1))
        
        // Check A in Segment 2
        let resolvedA = seg2.activeClips.first { $0.assetId == clip.assetId }
        XCTAssertNotNil(resolvedA)
        
        // A starts at 10 (Timeline) -> 100 (Source)
        // Segment starts at 15 (Timeline) -> Should be 105 (Source)
        XCTAssertEqual(resolvedA?.sourceRange.start, RationalTime(value: 105, timescale: 1))
        XCTAssertEqual(resolvedA?.sourceRange.duration, RationalTime(value: 5, timescale: 1))
    }
}
