import AVFoundation
import Accelerate

public class AudioAnalyzer {
    private let file: AVAudioFile
    private let buffer: AVAudioPCMBuffer
    private var amplitudeEnvelope: [Float] = []
    private let sampleRate: Double
    private let duration: Double
    
    public init(url: URL) throws {
        self.file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        self.sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(file.length)
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw AudioAnalysisError.bufferAllocationFailed
        }
        
        try file.read(into: buffer)
        self.buffer = buffer
        self.duration = Double(frameCount) / sampleRate
        
        // Pre-calculate envelope
        calculateEnvelope()
    }
    
    private func calculateEnvelope() {
        guard let channelData = buffer.floatChannelData else { return }
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        
        // We'll sample at 60fps for animation sync
        let samplesPerSecond = 60
        let totalSamples = Int(duration * Double(samplesPerSecond))
        let windowSize = Int(sampleRate / Double(samplesPerSecond))
        
        amplitudeEnvelope = [Float](repeating: 0, count: totalSamples)
        
        // Use the first channel (mono mix would be better but this is faster)
        let samples = UnsafeBufferPointer(start: channelData[0], count: frameLength)
        
        for i in 0..<totalSamples {
            let start = i * windowSize
            if start + windowSize >= frameLength { break }
            
            // Calculate RMS for this window
            var rms: Float = 0
            vDSP_rmsqv(samples.baseAddress! + start, 1, &rms, vDSP_Length(windowSize))
            
            amplitudeEnvelope[i] = rms
        }
        
        // Normalize? Maybe not, raw RMS is good for intensity.
        // But let's boost it a bit as raw RMS is usually low.
        // We can do this at runtime.
    }
    
    public func getAmplitude(at time: Double) -> Float {
        let samplesPerSecond = 60.0
        let index = Int(time * samplesPerSecond)
        
        if index >= 0 && index < amplitudeEnvelope.count {
            return amplitudeEnvelope[index]
        }
        return 0.0
    }
    
    public enum AudioAnalysisError: Error {
        case bufferAllocationFailed
    }
}
