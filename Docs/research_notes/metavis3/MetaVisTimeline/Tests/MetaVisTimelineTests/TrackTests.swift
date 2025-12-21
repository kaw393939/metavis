import XCTest
import MetaVisCore
@testable import MetaVisTimeline

final class TrackTests: XCTestCase {
    
    func testAddClip() throws {
        var track = Track(name: "Video 1")
        
        let range = TimeRange(start: RationalTime(value: 0, timescale: 1), duration: RationalTime(value: 10, timescale: 1))
        let clip = Clip(name: "Clip 1", assetId: UUID(), range: range, sourceStartTime: .zero)
        
        try track.add(clip)
        
        XCTAssertEqual(track.clips.count, 1)
        XCTAssertEqual(track.clips.first?.id, clip.id)
    }
    
    func testOverlapDetection() throws {
        var track = Track(name: "Video 1")
        
        // Clip A: 0-10
        let clipA = Clip(
            name: "A",
            assetId: UUID(),
            range: TimeRange(start: RationalTime(value: 0, timescale: 1), duration: RationalTime(value: 10, timescale: 1)),
            sourceStartTime: .zero
        )
        try track.add(clipA)
        
        // Clip B: 10-20 (Should succeed, adjacent)
        let clipB = Clip(
            name: "B",
            assetId: UUID(),
            range: TimeRange(start: RationalTime(value: 10, timescale: 1), duration: RationalTime(value: 10, timescale: 1)),
            sourceStartTime: .zero
        )
        try track.add(clipB)
        
        // Clip C: 5-15 (Overlap with A and B)
        let clipC = Clip(
            name: "C",
            assetId: UUID(),
            range: TimeRange(start: RationalTime(value: 5, timescale: 1), duration: RationalTime(value: 10, timescale: 1)),
            sourceStartTime: .zero
        )
        
        XCTAssertThrowsError(try track.add(clipC)) { error in
            XCTAssertEqual(error as? TimelineError, .clipOverlap)
        }
        
        // Clip D: 9-11 (Overlap with A and B)
        let clipD = Clip(
            name: "D",
            assetId: UUID(),
            range: TimeRange(start: RationalTime(value: 9, timescale: 1), duration: RationalTime(value: 2, timescale: 1)),
            sourceStartTime: .zero
        )
        XCTAssertThrowsError(try track.add(clipD))
    }
    
    func testFindClip() throws {
        var track = Track(name: "Video 1")
        
        let clipA = Clip(
            name: "A",
            assetId: UUID(),
            range: TimeRange(start: RationalTime(value: 0, timescale: 1), duration: RationalTime(value: 10, timescale: 1)),
            sourceStartTime: .zero
        )
        let clipB = Clip(
            name: "B",
            assetId: UUID(),
            range: TimeRange(start: RationalTime(value: 20, timescale: 1), duration: RationalTime(value: 10, timescale: 1)),
            sourceStartTime: .zero
        )
        
        try track.add(clipA)
        try track.add(clipB)
        
        // Find A
        let foundA = track.clip(at: RationalTime(value: 5, timescale: 1))
        XCTAssertEqual(foundA?.name, "A")
        
        // Find Gap (15s)
        let foundGap = track.clip(at: RationalTime(value: 15, timescale: 1))
        XCTAssertNil(foundGap)
        
        // Find B (Inclusive start)
        let foundB = track.clip(at: RationalTime(value: 20, timescale: 1))
        XCTAssertEqual(foundB?.name, "B")
        
        // Find B (Exclusive end)
        let foundEnd = track.clip(at: RationalTime(value: 30, timescale: 1))
        XCTAssertNil(foundEnd)
    }
    
    func testRemoveClip() throws {
        var track = Track(name: "Video 1")
        let clip = Clip(
            name: "A",
            assetId: UUID(),
            range: TimeRange(start: .zero, duration: RationalTime(value: 10, timescale: 1)),
            sourceStartTime: .zero
        )
        try track.add(clip)
        
        XCTAssertEqual(track.clips.count, 1)
        track.remove(id: clip.id)
        XCTAssertEqual(track.clips.count, 0)
    }
}
