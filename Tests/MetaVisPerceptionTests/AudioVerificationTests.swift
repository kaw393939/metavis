import XCTest
import AVFoundation
import MetaVisAudio
import MetaVisPerception

final class AudioVerificationTests: XCTestCase {
    
    func testClosedLoopVerification() async throws {
        // 1. The Mouth (Generator)
        let generator = AudioSignalGenerator()
        
        // 2. The Ears (Analyzer)
        let analyzer = AudioAnalyzer()
        
        // 3. Setup Expectation
        let expectation = XCTestExpectation(description: "Heard 1kHz Tone")
        
        // 4. Install Tap (The Wire)
        await generator.installTap { buffer, time in
            // This block runs on a realtime audio thread.
            // We must be careful. For test, we can just capture or analyze here?
            // Analyzer is an actor, so async call might be tricky in realtime block.
            // Better to capture buffer and process on test thread, or spin up a task.
            
            // For simple boolean verification:
            Task {
                let context = await analyzer.analyze(buffer: buffer)
                
                // Allow some tolerance for FFT bin width
                // 1024 FFT @ 44.1kHz -> ~43Hz bin width.
                // 1000Hz should be detected around 990-1033.
                
                if abs(context.dominantFrequency - 1000) < 50 && context.peakAmplitudeDB > -40 {
                    expectation.fulfill()
                }
            }
        }
        
        // 5. Speak
        try await generator.start(waveform: .sine(frequency: 1000), amplitude: 0.1)
        
        // 6. Wait for Perception
        await fulfillment(of: [expectation], timeout: 2.0)
        
        await generator.stop()
        await generator.removeTap()
    }
}
