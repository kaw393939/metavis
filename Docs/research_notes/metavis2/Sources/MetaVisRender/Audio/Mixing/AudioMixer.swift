// AudioMixer.swift
// MetaVisRender
//
// Created for Sprint 12: Audio Mixing
// Multi-track audio mixing engine

import Foundation
import AVFoundation
import Accelerate

// MARK: - MixerAudioBuffer

/// A buffer of audio samples for mixing operations
public struct MixerAudioBuffer: Sendable {
    /// Sample data per channel
    public var channels: [[Float]]
    
    /// Sample rate
    public let sampleRate: Double
    
    /// Number of channels
    public var channelCount: Int { channels.count }
    
    /// Number of samples per channel
    public var sampleCount: Int { channels.first?.count ?? 0 }
    
    /// Duration in seconds
    public var duration: Double {
        Double(sampleCount) / sampleRate
    }
    
    public init(channels: [[Float]], sampleRate: Double) {
        self.channels = channels
        self.sampleRate = sampleRate
    }
    
    /// Create empty buffer
    public static func empty(
        channelCount: Int = 2,
        sampleCount: Int = 1024,
        sampleRate: Double = 48000
    ) -> MixerAudioBuffer {
        let channels = (0..<channelCount).map { _ in [Float](repeating: 0, count: sampleCount) }
        return MixerAudioBuffer(channels: channels, sampleRate: sampleRate)
    }
    
    /// Create mono buffer
    public static func mono(samples: [Float], sampleRate: Double = 48000) -> MixerAudioBuffer {
        MixerAudioBuffer(channels: [samples], sampleRate: sampleRate)
    }
    
    /// Create stereo buffer
    public static func stereo(left: [Float], right: [Float], sampleRate: Double = 48000) -> MixerAudioBuffer {
        MixerAudioBuffer(channels: [left, right], sampleRate: sampleRate)
    }
    
    // MARK: - Processing
    
    /// Apply gain to all channels
    public func applyGain(_ gain: Float) -> MixerAudioBuffer {
        var result = self
        for i in 0..<result.channels.count {
            vDSP.multiply(gain, result.channels[i], result: &result.channels[i])
        }
        return result
    }
    
    /// Apply pan (-1 = left, 0 = center, 1 = right)
    public func applyPan(_ pan: Float) -> MixerAudioBuffer {
        guard channelCount >= 2 else { return self }
        
        var result = self
        
        // Constant power panning
        let angle = (pan + 1) * .pi / 4  // 0 to π/2
        let leftGain = cos(angle)
        let rightGain = sin(angle)
        
        vDSP.multiply(leftGain, result.channels[0], result: &result.channels[0])
        vDSP.multiply(rightGain, result.channels[1], result: &result.channels[1])
        
        return result
    }
    
    /// Mix with another buffer (sum)
    public func mixing(with other: MixerAudioBuffer) -> MixerAudioBuffer {
        guard sampleRate == other.sampleRate else { return self }
        
        var result = self
        let minChannels = min(channelCount, other.channelCount)
        let minSamples = min(sampleCount, other.sampleCount)
        
        for ch in 0..<minChannels {
            for s in 0..<minSamples {
                result.channels[ch][s] += other.channels[ch][s]
            }
        }
        
        return result
    }
    
    /// RMS level of buffer
    public func rmsLevel() -> Float {
        var totalRMS: Float = 0
        
        for channel in channels {
            var rms: Float = 0
            vDSP_measqv(channel, 1, &rms, vDSP_Length(channel.count))
            totalRMS += sqrt(rms)
        }
        
        return totalRMS / Float(channelCount)
    }
    
    /// Peak level of buffer
    public func peakLevel() -> Float {
        var maxPeak: Float = 0
        
        for channel in channels {
            var peak: Float = 0
            vDSP_maxmgv(channel, 1, &peak, vDSP_Length(channel.count))
            maxPeak = max(maxPeak, peak)
        }
        
        return maxPeak
    }
    
    /// Apply soft limiter to prevent clipping
    public func limited(threshold: Float = 0.95) -> MixerAudioBuffer {
        var result = self
        
        for ch in 0..<result.channels.count {
            for s in 0..<result.channels[ch].count {
                let sample = result.channels[ch][s]
                if abs(sample) > threshold {
                    // Soft clip using tanh
                    let sign: Float = sample > 0 ? 1 : -1
                    result.channels[ch][s] = sign * (threshold + (1 - threshold) * tanh((abs(sample) - threshold) / (1 - threshold)))
                }
            }
        }
        
        return result
    }
}

// MARK: - MixConfiguration

/// Configuration for audio mixing
public struct MixConfiguration: Codable, Sendable {
    /// Output sample rate
    public let sampleRate: Double
    
    /// Output channel count
    public let channelCount: Int
    
    /// Buffer size in samples
    public let bufferSize: Int
    
    /// Master volume
    public var masterVolume: Float
    
    /// Enable limiting on master bus
    public var limitingEnabled: Bool
    
    /// Limiter threshold
    public var limiterThreshold: Float
    
    public init(
        sampleRate: Double = 48000,
        channelCount: Int = 2,
        bufferSize: Int = 1024,
        masterVolume: Float = 1.0,
        limitingEnabled: Bool = true,
        limiterThreshold: Float = 0.95
    ) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.bufferSize = bufferSize
        self.masterVolume = masterVolume
        self.limitingEnabled = limitingEnabled
        self.limiterThreshold = limiterThreshold
    }
    
    public static let `default` = MixConfiguration()
    
    public static let highQuality = MixConfiguration(
        sampleRate: 96000,
        channelCount: 2,
        bufferSize: 2048
    )
}

// MARK: - TrackState

/// Runtime state for a track
public struct TrackState: Sendable {
    public let id: AudioTrackID
    public var volume: Float
    public var pan: Float
    public var muted: Bool
    public var solo: Bool
    
    public init(
        id: AudioTrackID,
        volume: Float = 1.0,
        pan: Float = 0,
        muted: Bool = false,
        solo: Bool = false
    ) {
        self.id = id
        self.volume = volume
        self.pan = pan
        self.muted = muted
        self.solo = solo
    }
    
    public static func from(_ track: AudioTrack) -> TrackState {
        TrackState(
            id: track.id,
            volume: track.volume,
            pan: track.pan,
            muted: track.muted,
            solo: track.solo
        )
    }
}

// MARK: - AudioMixer

/// Multi-track audio mixing engine
///
/// Combines multiple audio tracks into a final stereo mix with
/// volume automation, panning, and limiting.
///
/// ## Example
/// ```swift
/// let mixer = AudioMixer(configuration: .default)
/// 
/// await mixer.addTrack(AudioTrack.music(id: "music"))
/// await mixer.addTrack(AudioTrack.voiceover(id: "vo"))
/// 
/// let buffers: [AudioTrackID: MixerAudioBuffer] = [...]
/// let mixed = try await mixer.mix(trackBuffers: buffers, time: 45.0)
/// ```
@available(*, deprecated, message: "Use MetaVisAudioEngine instead. This class is not optimized for Apple Silicon.")
public actor AudioMixer {
    
    // MARK: - Properties
    
    /// Mix configuration
    public let configuration: MixConfiguration
    
    /// Track states
    private var trackStates: [AudioTrackID: TrackState] = [:]
    
    /// Ducking processor (optional)
    private var duckingProcessor: DuckingProcessor?
    
    /// Track IDs that trigger ducking
    private var duckingTriggers: Set<AudioTrackID> = []
    
    /// Track IDs that are ducked
    private var duckingTargets: Set<AudioTrackID> = []
    
    // MARK: - Initialization
    
    public init(configuration: MixConfiguration = .default) {
        self.configuration = configuration
    }
    
    // MARK: - Track Management
    
    /// Add a track to the mixer
    public func addTrack(_ track: AudioTrack) {
        trackStates[track.id] = TrackState.from(track)
        
        // Track ducking roles
        if track.type.triggersDucking {
            duckingTriggers.insert(track.id)
        }
        if track.type.isDuckingTarget {
            duckingTargets.insert(track.id)
        }
    }
    
    /// Remove a track
    public func removeTrack(id: AudioTrackID) {
        trackStates.removeValue(forKey: id)
        duckingTriggers.remove(id)
        duckingTargets.remove(id)
    }
    
    /// Set track volume
    public func setVolume(_ volume: Float, for trackID: AudioTrackID) {
        trackStates[trackID]?.volume = volume.clamped(to: 0...2)
    }
    
    /// Set track pan
    public func setPan(_ pan: Float, for trackID: AudioTrackID) {
        trackStates[trackID]?.pan = pan.clamped(to: -1...1)
    }
    
    /// Mute a track
    public func mute(_ trackID: AudioTrackID) {
        trackStates[trackID]?.muted = true
    }
    
    /// Unmute a track
    public func unmute(_ trackID: AudioTrackID) {
        trackStates[trackID]?.muted = false
    }
    
    /// Solo a track
    public func solo(_ trackID: AudioTrackID) {
        trackStates[trackID]?.solo = true
    }
    
    /// Unsolo a track
    public func unsolo(_ trackID: AudioTrackID) {
        trackStates[trackID]?.solo = false
    }
    
    /// Unsolo all tracks
    public func unsoloAll() {
        for id in trackStates.keys {
            trackStates[id]?.solo = false
        }
    }
    
    // MARK: - Ducking
    
    /// Configure ducking processor
    public func configureDucking(_ config: DuckingConfiguration) {
        duckingProcessor = DuckingProcessor(configuration: config)
    }
    
    /// Disable ducking
    public func disableDucking() {
        duckingProcessor = nil
    }
    
    // MARK: - Mixing
    
    /// Mix track buffers at a specific time
    public func mix(
        trackBuffers: [AudioTrackID: MixerAudioBuffer],
        time: Double
    ) async throws -> MixerAudioBuffer {
        // Create empty output buffer
        var mixBuffer = MixerAudioBuffer.empty(
            channelCount: configuration.channelCount,
            sampleCount: configuration.bufferSize,
            sampleRate: configuration.sampleRate
        )
        
        // Check for solo tracks
        let soloedTracks = trackStates.filter { $0.value.solo }.map { $0.key }
        let hasSolo = !soloedTracks.isEmpty
        
        // Separate buffers for ducking
        var triggerBuffers: [MixerAudioBuffer] = []
        var targetBuffers: [(id: AudioTrackID, buffer: MixerAudioBuffer)] = []
        var otherBuffers: [MixerAudioBuffer] = []
        
        // Process each track
        for (trackID, buffer) in trackBuffers {
            guard let state = trackStates[trackID] else { continue }
            
            // Skip muted tracks
            if state.muted { continue }
            
            // If solo is active, only play soloed tracks
            if hasSolo && !state.solo { continue }
            
            // Apply track volume and pan
            let processed = buffer
                .applyGain(state.volume)
                .applyPan(state.pan)
            
            // Categorize for ducking
            if duckingTriggers.contains(trackID) {
                triggerBuffers.append(processed)
                otherBuffers.append(processed)
            } else if duckingTargets.contains(trackID) {
                targetBuffers.append((trackID, processed))
            } else {
                otherBuffers.append(processed)
            }
        }
        
        // Apply ducking to target tracks
        if let ducker = duckingProcessor {
            let duckAmount = ducker.calculateDuckAmount(triggerBuffers: triggerBuffers)
            
            for (_, buffer) in targetBuffers {
                let ducked = buffer.applyGain(duckAmount)
                otherBuffers.append(ducked)
            }
        } else {
            // No ducking, add targets directly
            for (_, buffer) in targetBuffers {
                otherBuffers.append(buffer)
            }
        }
        
        // Sum all buffers
        for buffer in otherBuffers {
            mixBuffer = mixBuffer.mixing(with: buffer)
        }
        
        // Apply master volume
        mixBuffer = mixBuffer.applyGain(configuration.masterVolume)
        
        // Apply limiting
        if configuration.limitingEnabled {
            mixBuffer = mixBuffer.limited(threshold: configuration.limiterThreshold)
        }
        
        return mixBuffer
    }
    
    // MARK: - Queries
    
    /// Get current track state
    public func trackState(for id: AudioTrackID) -> TrackState? {
        trackStates[id]
    }
    
    /// Get all track IDs
    public var allTrackIDs: [AudioTrackID] {
        Array(trackStates.keys)
    }
    
    /// Check if any track is soloed
    public var hasSoloedTrack: Bool {
        trackStates.values.contains { $0.solo }
    }
}

// MARK: - DuckingConfiguration

/// Configuration for auto-ducking
public struct DuckingConfiguration: Codable, Sendable {
    /// Whether ducking is enabled
    public var enabled: Bool
    
    /// Amount to reduce volume in dB (negative value)
    public var duckLevelDB: Float
    
    /// Time to fade down when speech starts
    public var attackTime: Double
    
    /// Time to fade up when speech ends
    public var releaseTime: Double
    
    /// RMS threshold for speech detection in dB
    public var thresholdDB: Float
    
    public init(
        enabled: Bool = true,
        duckLevelDB: Float = -12,
        attackTime: Double = 0.3,
        releaseTime: Double = 0.5,
        thresholdDB: Float = -30
    ) {
        self.enabled = enabled
        self.duckLevelDB = duckLevelDB
        self.attackTime = attackTime
        self.releaseTime = releaseTime
        self.thresholdDB = thresholdDB
    }
    
    public static let `default` = DuckingConfiguration()
    
    public static let aggressive = DuckingConfiguration(
        duckLevelDB: -18,
        attackTime: 0.1,
        releaseTime: 0.3
    )
    
    public static let subtle = DuckingConfiguration(
        duckLevelDB: -6,
        attackTime: 0.5,
        releaseTime: 1.0
    )
}

// MARK: - DuckingProcessor

/// Processes audio for automatic ducking
public struct DuckingProcessor: Sendable {
    
    public let configuration: DuckingConfiguration
    
    public init(configuration: DuckingConfiguration) {
        self.configuration = configuration
    }
    
    /// Calculate duck amount based on trigger buffers
    public func calculateDuckAmount(triggerBuffers: [MixerAudioBuffer]) -> Float {
        guard configuration.enabled else { return 1.0 }
        
        // Check if any trigger has signal above threshold
        let speechPresent = triggerBuffers.contains { buffer in
            let rms = buffer.rmsLevel()
            let rmsDB = linearToDB(rms)
            return rmsDB > configuration.thresholdDB
        }
        
        if speechPresent {
            // Duck to configured level
            return dBToLinear(configuration.duckLevelDB)
        } else {
            // Full volume
            return 1.0
        }
    }
}
