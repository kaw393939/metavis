import XCTest
@testable import MetaVisAudio
import MetaVisCore
import MetaVisTimeline
import AVFoundation

final class AutoMasteringTests: XCTestCase {
    
    func testEngineerOptimizesLevels() async throws {
        // 1. Create a Quiet Clip (-20dB approx)
        // Sine wave at amplitude 0.1 is -20dBFS relative to 1.0 peak
        // 20*log10(0.1) = -20 dB.
        let clip = Clip(
            name: "Quiet Sine",
            asset: AssetReference(sourceFn: "ligm://sine?freq=440"),
            startTime: .zero,
            duration: Time(seconds: 1.0)
        )
        let timeline = Timeline(tracks: [Track(name: "A1", kind: .audio, clips: [clip])], duration: Time(seconds: 1.0))
        
        // 2. Setup
        let renderer = AudioTimelineRenderer()
        let agent = EngineerAgent()
        
        // 3. Run Optimization (Target -14 LUFS)
        try await agent.optimize(timeline: timeline, renderer: renderer, governance: .spotify)
        
        // 4. Render FINAL pass
        let finalBuffer = try await renderer.render(timeline: timeline, timeRange: Time.zero..<Time(seconds: 1.0))
        
        // 5. Verify Levels increased
        let analyzer = LoudnessAnalyzer()
        let result = analyzer.analyze(buffer: finalBuffer!)
        
        print("TEST RESULT: Final LUFS: \(result.lufs)")
        
        // Input was -20dB (RMS of Sine 0.1 is 0.0707 -> -23dB actually).
        // Target -14dB.
        // We expect a boost.
        
        XCTAssertGreaterThan(result.lufs, -20.0, "Audio should have been boosted")
        // It might not exact hit -14 depending on how dynamics processor reacts to sine wave (RMS vs Peak detection), 
        // but it should be significantly louder than -23.
    }
}
