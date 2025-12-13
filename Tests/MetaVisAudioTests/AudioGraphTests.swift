import XCTest
@testable import MetaVisAudio
import MetaVisCore
import MetaVisTimeline
import AVFoundation

final class AudioGraphTests: XCTestCase {
    
    func testGraphConstruction() throws {
        // 1. Create a Timeline
        let clip = Clip(
            name: "Sine Element",
            asset: AssetReference(sourceFn: "ligm://sine?freq=440"),
            startTime: .zero,
            duration: Time(seconds: 1.0)
        )
        let track = Track(name: "Audio 1", kind: .audio, clips: [clip])
        let timeline = Timeline(tracks: [track], duration: Time(seconds: 1.0))
        
        // 2. Render
        let renderer = AudioTimelineRenderer()
        let buffer = try renderer.render(timeline: timeline, timeRange: Time.zero..<Time(seconds: 0.5))
        
        // 3. Verify
        XCTAssertNotNil(buffer)
        XCTAssertEqual(buffer?.frameLength, 24000) // 0.5s * 48k
        
        // Check for non-silence
        guard let channels = buffer?.floatChannelData else {
            XCTFail("No channel data")
            return
        }
        
        let pointer = channels[0]
        var hasSignal = false
        // Check middle of buffer to avoid phase 0
        for i in 1000..<2000 {
            if abs(pointer[i]) > 0.0001 {
                hasSignal = true
                break
            }
        }
        
        XCTAssertTrue(hasSignal, "Buffer should contain audio signal")
    }
    
    func testMixing() throws {
        // Two sine waves
        let clip1 = Clip(
            name: "Sine 1",
            asset: AssetReference(sourceFn: "ligm://sine?freq=440"), // Phase 0 starts at 0
            startTime: .zero,
            duration: Time(seconds: 1.0)
        )
        
        let clip2 = Clip(
            name: "Sine 2",
            asset: AssetReference(sourceFn: "ligm://sine?freq=440"),
            startTime: .zero,
            duration: Time(seconds: 1.0)
        )
        
        let track1 = Track(name: "A1", kind: .audio, clips: [clip1])
        let track2 = Track(name: "A2", kind: .audio, clips: [clip2])
        let timeline = Timeline(tracks: [track1, track2], duration: Time(seconds: 1.0))
        
        let renderer = AudioTimelineRenderer()
        let buffer = try renderer.render(timeline: timeline, timeRange: Time.zero..<Time(seconds: 0.1))
        
        XCTAssertNotNil(buffer)
        
        // Signal should be roughly double amplitude? 
        // 0.1 + 0.1 = 0.2 approx?
        // Note: Mixers prevent clipping sometimes? 
        // AVAudioEngine main mixer usually sums float.
        
        let data = buffer!.floatChannelData![0]
        // sin(small) approx small.
        // at sample 100:
        // phase roughly 100/48000 * 440 * 2pi
        // val = sin * 0.1
        
        // Let's just check it's louder than single clip?
        // Or check existence.
        
        XCTAssertTrue(abs(data[1000]) > 0.001)
    }
}
