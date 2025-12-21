import Foundation
import AVFoundation

/// Handles loading of audio assets, specifically FLAC.
public class AudioLoader {
    
    public init() {}
    
    /// Loads an audio file and returns the PCM buffer.
    /// Supports FLAC via CoreAudio.
    public func loadAudio(url: URL) throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "MetaVisAudio", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio buffer"])
        }
        
        try file.read(into: buffer)
        return buffer
    }
}
