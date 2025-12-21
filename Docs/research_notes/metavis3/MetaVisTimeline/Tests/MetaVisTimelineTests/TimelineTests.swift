import XCTest
import MetaVisCore
@testable import MetaVisTimeline

final class TimelineTests: XCTestCase {
    
    func testTimelineManagement() {
        var timeline = Timeline(name: "Main Sequence")
        let track = Track(name: "V1")
        
        timeline.addTrack(track)
        XCTAssertEqual(timeline.tracks.count, 1)
        
        timeline.removeTrack(id: track.id)
        XCTAssertTrue(timeline.tracks.isEmpty)
    }
    
    func testDurationCalculation() throws {
        var timeline = Timeline(name: "Main Sequence")
        var track1 = Track(name: "V1")
        var track2 = Track(name: "V2")
        
        // Track 1: 0-10
        let clip1 = Clip(
            name: "C1",
            assetId: UUID(),
            range: TimeRange(start: .zero, duration: RationalTime(value: 10, timescale: 1)),
            sourceStartTime: .zero
        )
        try track1.add(clip1)
        
        // Track 2: 5-15
        let clip2 = Clip(
            name: "C2",
            assetId: UUID(),
            range: TimeRange(start: RationalTime(value: 5, timescale: 1), duration: RationalTime(value: 10, timescale: 1)),
            sourceStartTime: .zero
        )
        try track2.add(clip2)
        
        timeline.addTrack(track1)
        timeline.addTrack(track2)
        
        // Duration should be max end time (15)
        XCTAssertEqual(timeline.duration, RationalTime(value: 15, timescale: 1))
        
        // Add later clip to Track 1: 20-30
        let clip3 = Clip(
            name: "C3",
            assetId: UUID(),
            range: TimeRange(start: RationalTime(value: 20, timescale: 1), duration: RationalTime(value: 10, timescale: 1)),
            sourceStartTime: .zero
        )
        
        // Update track in timeline
        var updatedTrack1 = timeline.tracks[0]
        try updatedTrack1.add(clip3)
        timeline.tracks[0] = updatedTrack1
        
        XCTAssertEqual(timeline.duration, RationalTime(value: 30, timescale: 1))
    }
    
    func testActiveClips() throws {
        var timeline = Timeline(name: "Main Sequence")
        var track1 = Track(name: "V1")
        var track2 = Track(name: "V2")
        
        let clip1 = Clip(
            name: "C1",
            assetId: UUID(),
            range: TimeRange(start: .zero, duration: RationalTime(value: 10, timescale: 1)),
            sourceStartTime: .zero
        )
        try track1.add(clip1)
        
        let clip2 = Clip(
            name: "C2",
            assetId: UUID(),
            range: TimeRange(start: RationalTime(value: 5, timescale: 1), duration: RationalTime(value: 10, timescale: 1)),
            sourceStartTime: .zero
        )
        try track2.add(clip2)
        
        timeline.addTrack(track1)
        timeline.addTrack(track2)
        
        // At t=2: Only C1
        let active2 = timeline.activeClips(at: RationalTime(value: 2, timescale: 1))
        XCTAssertEqual(active2.count, 1)
        XCTAssertEqual(active2.first?.name, "C1")
        
        // At t=7: C1 and C2
        let active7 = timeline.activeClips(at: RationalTime(value: 7, timescale: 1))
        XCTAssertEqual(active7.count, 2)
    }
    
    func testPerformance_TimelineResolution() {
        // Create a timeline with many tracks and clips
        var timeline = Timeline(name: "Perf Timeline")
        
        for i in 0..<100 {
            var track = Track(name: "Track \(i)")
            for j in 0..<10 {
                let start = RationalTime(value: Int64(j * 100), timescale: 24)
                let duration = RationalTime(value: 50, timescale: 24)
                let clip = Clip(
                    name: "Clip \(i)-\(j)",
                    assetId: UUID(),
                    range: TimeRange(start: start, duration: duration),
                    sourceStartTime: .zero
                )
                try? track.add(clip)
            }
            timeline.addTrack(track)
        }
        
        measure {
            // Resolve active clips at a specific time
            let time = RationalTime(value: 500, timescale: 24)
            let active = timeline.activeClips(at: time)
            // Should find clips in the middle of each track
            XCTAssertEqual(active.count, 100)
        }
    }
    
    func testEdgeCase_EmptyTimeline() {
        let timeline = Timeline(name: "Empty")
        XCTAssertEqual(timeline.duration, .zero)
        XCTAssertTrue(timeline.activeClips(at: .zero).isEmpty)
    }
}
        let active7 = timeline.activeClips(at: RationalTime(value: 7, timescale: 1))
        XCTAssertEqual(active7.count, 2)
        XCTAssertTrue(active7.contains { $0.name == "C1" })
        XCTAssertTrue(active7.contains { $0.name == "C2" })
        
        // At t=12: Only C2
        let active12 = timeline.activeClips(at: RationalTime(value: 12, timescale: 1))
        XCTAssertEqual(active12.count, 1)
        XCTAssertEqual(active12.first?.name, "C2")
    }
}
