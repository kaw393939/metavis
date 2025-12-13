import Foundation
import AVFoundation
import Accelerate

public struct AudioAnalysis: Sendable {
    public let lufs: Float // Approximate using RMS for V1
    public let peak: Float // dB
}

/// The "Ears" of the system.
public struct LoudnessAnalyzer {
    
    public init() {}
    
    public func analyze(buffer: AVAudioPCMBuffer) -> AudioAnalysis {
        guard let channelData = buffer.floatChannelData else {
            return AudioAnalysis(lufs: -100.0, peak: -100.0)
        }
        
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        
        var totalRMS: Float = 0.0
        var globalPeak: Float = 0.0
        
        // Process each channel
        for ch in 0..<channelCount {
            let channelPtr = channelData[ch]

            // 1. Calculate Peak Magnitude (abs)
            var channelMaxMag: Float = 0.0
            vDSP_maxmgv(channelPtr, 1, &channelMaxMag, vDSP_Length(frameLength))
            
            if channelMaxMag > globalPeak {
                globalPeak = channelMaxMag
            }
            
            // 2. Calculate Mean Square
            var channelMeanSquare: Float = 0.0
            vDSP_measqv(channelPtr, 1, &channelMeanSquare, vDSP_Length(frameLength))
            totalRMS += channelMeanSquare
        }
        
        let avgMeanSquare = totalRMS / Float(channelCount)
        let rms = sqrt(avgMeanSquare)
        
        // Convert to dB
        // dB = 20 * log10(amplitude)
        let peakDB = globalPeak > 0 ? 20.0 * log10(globalPeak) : -100.0
        let rmsDB = rms > 0 ? 20.0 * log10(rms) : -100.0
        
        return AudioAnalysis(lufs: rmsDB, peak: peakDB)
    }
}
