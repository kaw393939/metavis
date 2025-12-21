// AudioTrackNode.swift
// MetaVisRender
//
// Created for Audio Re-architecture (Phase 1)

import AVFoundation

/// A node representing a single audio track in the graph.
///
/// Wraps an `AVAudioPlayerNode` and its associated effects chain.
/// Responsible for scheduling buffers and managing track-level DSP.
public class AudioTrackNode {
    
    // MARK: - Properties
    
    /// The source player node.
    public let player: AVAudioPlayerNode
    
    /// The equalizer unit (first in chain).
    public let eq: AVAudioUnitEQ
    
    /// The limiter/compressor unit (second in chain).
    /// Uses AVAudioUnitEffect with kAudioUnitSubType_DynamicsProcessor
    public let compressor: AVAudioUnitEffect
    
    /// The output node of this track's local chain (usually the compressor).
    public var outputNode: AVAudioNode { compressor }
    
    /// The engine this track belongs to.
    private weak var engine: AVAudioEngine?
    
    // MARK: - Initialization
    
    public init(engine: AVAudioEngine) {
        self.engine = engine
        self.player = AVAudioPlayerNode()
        self.eq = AVAudioUnitEQ(numberOfBands: 3)
        
        // Create a dynamics processor using AudioComponentDescription
        let desc = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        self.compressor = AVAudioUnitEffect(audioComponentDescription: desc)
        
        setupChain()
    }
    
    private func setupChain() {
        guard let engine = engine else { return }
        
        // Attach nodes
        engine.attach(player)
        engine.attach(eq)
        engine.attach(compressor)
        
        // Connect: Player -> EQ -> Compressor
        // Note: Connection to the main mixer/bus happens externally
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(player, to: eq, format: format)
        engine.connect(eq, to: compressor, format: format)
    }
    
    // MARK: - Scheduling
    
    /// Schedule a buffer to play at a specific time.
    /// - Parameters:
    ///   - buffer: The PCM buffer to play.
    ///   - time: The time in the timeline to play (seconds).
    ///   - sampleRate: The sample rate of the timeline.
    public func schedule(buffer: AVAudioPCMBuffer, at time: TimeInterval, sampleRate: Double) {
        let sampleTime = AVAudioFramePosition(time * sampleRate)
        let timestamp = AVAudioTime(sampleTime: sampleTime, atRate: sampleRate)
        
        player.scheduleBuffer(buffer, at: timestamp, options: .interrupts, completionHandler: nil)
    }
    
    /// Start playback.
    public func play() {
        player.play()
    }
    
    /// Stop playback.
    public func stop() {
        player.stop()
    }
    
    // MARK: - Effects Control
    
    public func setVolume(_ volume: Float) {
        player.volume = volume
    }
    
    public func setPan(_ pan: Float) {
        player.pan = pan
    }
}
