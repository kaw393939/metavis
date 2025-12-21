import XCTest
import MetaVisCore
@testable import MetaVisTimeline

final class TrackDebtTests: XCTestCase {
    
    func testBinarySearchPerformance() {
        // Create a track with many clips
        var track = Track(name: "Performance Track")
        let count = 1000
        
        for i in 0..<count {
            let start = RationalTime(value: Int64(i * 10), timescale: 1)
            let duration = RationalTime(value: 5, timescale: 1)
            let clip = Clip(
                name: "Clip \(i)",
                assetId: UUID(),
                range: TimeRange(start: start, duration: duration),
                sourceStartTime: .zero
            )
            try? track.add(clip)
        }
        
        // Measure lookup time (Linear vs Binary)
        // We can't easily measure internal implementation, but we can verify correctness
        // and ensure it works for edge cases.
        
        // Test First
        let first = track.clip(at: RationalTime(value: 2, timescale: 1))
        XCTAssertEqual(first?.name, "Clip 0")
        
        // Test Last
        let lastTime = RationalTime(value: Int64((count - 1) * 10 + 2), timescale: 1)
        let last = track.clip(at: lastTime)
        XCTAssertEqual(last?.name, "Clip \(count - 1)")
        
        // Test Gap
        let gapTime = RationalTime(value: 7, timescale: 1) // 0-5 is clip, 5-10 is gap
        XCTAssertNil(track.clip(at: gapTime))
    }
    
    func testMutationSafety() throws {
        var track = Track(name: "Safety Track")
        
        let clipA = Clip(
            name: "A",
            assetId: UUID(),
            range: TimeRange(start: RationalTime(value: 0, timescale: 1), duration: RationalTime(value: 10, timescale: 1)),
            sourceStartTime: .zero
        )
        try track.add(clipA)
        let clipB = Clip(
            name: "B",
            assetId: UUID(),
            range: TimeRange(start: RationalTime(value: 20, timescale: 1), duration: RationalTime(value: 10, timescale: 1)),
            sourceStartTime: .zero
        )
        try track.add(clipB)
        
        // Try to move A to overlap B using a hypothetical update method
        // Since we don't have one yet, we can't test it.
        // This test serves as a placeholder for the TDD of `updateClip`.
        
        XCTAssertThrowsError(try track.updateClip(id: clipA.id) { clip in
            clip.move(to: RationalTime(value: 15, timescale: 1)) // Overlaps B (20-30)
        }) { error in
            XCTAssertEqual(error as? TimelineError, .clipOverlap)
        }
        
        // Verify A didn't move
        let checkA = track.clip(at: RationalTime(value: 0, timescale: 1))
        XCTAssertNotNil(checkA)
    }
}
