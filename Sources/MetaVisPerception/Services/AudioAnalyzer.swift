import Foundation
import AVFoundation
import Accelerate

/// Represents the perceived audio context.
public struct AudioContext: Sendable, Codable, Equatable {
    public let dominantFrequency: Float
    public let peakAmplitudeDB: Float
    public let classification: String // "Sine", "Noise", "Silence"
}

/// "The Ears" of the system. Analyzes audio buffers to extract semantic meaning.
public actor AudioAnalyzer {
    
    // FFT State
    private let fftSize: Int = 1024
    private var fftSetup: vDSP_DFT_Setup?
    
    public init() {
        // Setup FFT
        fftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(fftSize), vDSP_DFT_Direction.FORWARD)
    }
    
    deinit {
        if let setup = fftSetup {
            vDSP_DFT_DestroySetup(setup)
        }
    }
    
    /// Analyzes a buffer and returns the Audio Context.
    public func analyze(buffer: AVAudioPCMBuffer) -> AudioContext {
        guard let floatData = buffer.floatChannelData else {
            return AudioContext(dominantFrequency: 0, peakAmplitudeDB: -100, classification: "Error")
        }
        
        let frameCount = Int(buffer.frameLength)
        if frameCount < fftSize {
            // Buffer too small
             return AudioContext(dominantFrequency: 0, peakAmplitudeDB: -100, classification: "Silence")
        }
        
        // 1. Copy data to input buffer (Mono mixdown for analysis)
        // Taking first channel for simplicity
        let channelData = UnsafeBufferPointer(start: floatData[0], count: frameCount)
        var inputReal = [Float](repeating: 0, count: fftSize)
        var inputImag = [Float](repeating: 0, count: fftSize)
        
        // Copy windowed segment
        for i in 0..<fftSize {
            inputReal[i] = channelData[i]
        }
        
        // 2. Perform FFT
        var outputReal = [Float](repeating: 0, count: fftSize)
        var outputImag = [Float](repeating: 0, count: fftSize)
        
        guard let setup = fftSetup else { return AudioContext(dominantFrequency: 0, peakAmplitudeDB: -100, classification: "Error") }
        
        vDSP_DFT_Execute(setup, &inputReal, &inputImag, &outputReal, &outputImag)
        
        // 3. Compute Magnitude
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)
        
        outputReal.withUnsafeMutableBufferPointer { realPtr in
            outputImag.withUnsafeMutableBufferPointer { imagPtr in
                var complexSplit = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                vDSP_zvabs(&complexSplit, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }
        
        // 4. Find Peak
        var maxVal: Float = 0
        var maxIndex: vDSP_Length = 0
        vDSP_maxvi(&magnitudes, 1, &maxVal, &maxIndex, vDSP_Length(fftSize / 2))
        
        // 5. Convert to Frequency & DB
        let sampleRate = buffer.format.sampleRate
        let nyquist = sampleRate / 2.0
        let binWidth = nyquist / Double(fftSize / 2)
        let freq = Float(Double(maxIndex) * binWidth)
        
        // Amplitude (approx)
        let db = 20 * log10(maxVal + 1e-6) // Normalized? Not really, raw FFT mag. 
        // Roughly simplified for context matching.
        
        // 6. Classify
        let classification: String
        print("Detected Freq: \(freq), Mag: \(maxVal)")
        
        if maxVal < 0.01 {
            classification = "Silence"
        } else {
            // Simple heuristic
            classification = "Tone" 
            // In real impl, check harmonicity for Noise vs Tone
        }
        
        return AudioContext(dominantFrequency: freq, peakAmplitudeDB: db, classification: classification)
    }
}
