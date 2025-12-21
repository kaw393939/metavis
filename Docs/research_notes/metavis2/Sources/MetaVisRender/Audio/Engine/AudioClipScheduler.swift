// AudioClipScheduler.swift
// MetaVisRender
//
// Created for Audio Re-architecture (Phase 1)

import AVFoundation

/// Bridges `AudioClipDefinition` to `AudioTrackNode`.
///
/// Responsible for:
/// 1. Loading audio files (or retrieving from cache).
/// 2. Scheduling the correct segment on the player node.
/// 3. Applying volume/pan automation.
public actor AudioClipScheduler {
    
    // MARK: - Properties
    
    private let engine: MetaVisAudioEngine
    
    // MARK: - Initialization
    
    public init(engine: MetaVisAudioEngine) {
        self.engine = engine
    }
    
    // MARK: - Scheduling
    
    /// Schedule a clip on a track node.
    /// - Parameters:
    ///   - clip: The clip definition.
    ///   - trackNode: The target track node.
    ///   - resolveSource: Closure to resolve source string to URL.
    public func schedule(
        clip: AudioClipDefinition,
        on trackNode: AudioTrackNode,
        resolveSource: (String) throws -> URL
    ) async throws {
        guard clip.enabled else { return }
        
        // 1. Resolve URL
        let url = try resolveSource(clip.source)
        
        // 2. Open File
        let file = try AVAudioFile(forReading: url)
        
        // 3. Calculate Segment
        let sampleRate = file.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(clip.sourceIn * sampleRate)
        let frameCount = AVAudioFrameCount((clip.sourceOut - clip.sourceIn) * sampleRate)
        
        guard startFrame + AVAudioFramePosition(frameCount) <= file.length else {
            print("[AudioClipScheduler] Warning: Clip segment out of bounds for \(clip.source)")
            return
        }
        
        // 4. Schedule Segment
        // Note: We use scheduleSegment instead of scheduleBuffer for efficiency with large files.
        // For speed changes, we would need to use a Varispeed node or time pitch, 
        // but for Phase 1 we assume 1.0x speed or handle it later.
        
        let timelineTime = AVAudioTime(
            sampleTime: AVAudioFramePosition(clip.timelineIn * engine.configuration.sampleRate),
            atRate: engine.configuration.sampleRate
        )
        
        trackNode.player.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: frameCount,
            at: timelineTime,
            completionHandler: nil
        )
        
        // 5. Apply Static Properties (Volume/Pan)
        // Note: Automation would require scheduling parameter ramps.
        trackNode.setVolume(clip.volume)
        trackNode.setPan(clip.pan)
    }
}
