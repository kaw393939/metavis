import Foundation
import AVFoundation
import MetaVisAudio

public class AudioWaveformProvider {
    private let loader = AudioLoader()
    private var audioBuffer: AVAudioPCMBuffer?
    private var sampleRate: Double = 48000
    
    public init() {}
    
    public func load(url: URL) {
        do {
            self.audioBuffer = try loader.loadAudio(url: url)
            self.sampleRate = audioBuffer?.format.sampleRate ?? 48000
            print("Loaded Audio: \(url.lastPathComponent) (\(audioBuffer?.frameLength ?? 0) frames)")
        } catch {
            print("Failed to load audio: \(error)")
        }
    }
    
    /// Returns a normalized array of samples [-1.0, 1.0] for the given time window.
    /// - Parameters:
    ///   - time: Center time in seconds.
    ///   - duration: Duration of the window in seconds.
    ///   - samplesCount: Number of samples to return (downsampled).
    public func getWaveform(at time: Double, duration: Double, samplesCount: Int) -> [Float] {
        guard let buffer = audioBuffer, let channelData = buffer.floatChannelData else {
            return Array(repeating: 0.0, count: samplesCount)
        }
        
        let totalFrames = Int(buffer.frameLength)
        let startFrame = Int((time - duration/2) * sampleRate)
        let endFrame = Int((time + duration/2) * sampleRate)
        let framesToRead = endFrame - startFrame
        
        if framesToRead <= 0 { return Array(repeating: 0.0, count: samplesCount) }
        
        var output = [Float](repeating: 0.0, count: samplesCount)
        let samplesPerPixel = Double(framesToRead) / Double(samplesCount)
        
        let ptr = channelData[0] // Mono / Left channel
        
        for i in 0..<samplesCount {
            let frameIndex = startFrame + Int(Double(i) * samplesPerPixel)
            
            if frameIndex >= 0 && frameIndex < totalFrames {
                // Simple point sampling (aliased but fast)
                // TODO: Min/Max sampling for better visual
                output[i] = ptr[frameIndex]
            }
        }
        
        return output
    }
}
