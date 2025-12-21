// SpatialRenderer.swift
// MetaVisRender
//
// Created for Sprint 07: Spatial Audio
// 3D audio rendering using AVAudioEngine

import Foundation
import AVFoundation
import CoreMedia
import simd

// MARK: - Spatial Renderer

/// Real-time 3D audio rendering using AVAudioEngine
public actor SpatialRenderer {
    
    // MARK: - Types
    
    public enum Error: Swift.Error {
        case engineStartFailed(underlying: Swift.Error)
        case bufferCreationFailed
        case sourceNotFound(UUID)
        case renderFailed(String)
        case invalidFormat
        case noSources
    }
    
    /// Handle for a created audio source
    public struct AudioSourceHandle: Sendable {
        public let id: UUID
        public let personId: UUID
    }
    
    // MARK: - Audio Graph Components
    
    private var engine: AVAudioEngine?
    private var environmentNode: AVAudioEnvironmentNode?
    private var playerNodes: [UUID: AVAudioPlayerNode] = [:]
    private var mixerNodes: [UUID: AVAudioMixerNode] = [:]
    private var audioBuffers: [UUID: AVAudioPCMBuffer] = [:]
    
    // MARK: - State
    
    private var activePositions: [UUID: SpatialPosition] = [:]
    private var isEngineRunning = false
    
    // MARK: - Configuration
    
    private let outputFormat: AVAudioFormat
    
    // MARK: - Initialization
    
    public init(sampleRate: Double = 48000) throws {
        self.outputFormat = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 2
        )!
        
        // Setup audio graph
        let engine = AVAudioEngine()
        let environment = AVAudioEnvironmentNode()
        
        // Configure listener at origin, facing -Z
        environment.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
        environment.listenerVectorOrientation = AVAudio3DVectorOrientation(
            forward: AVAudio3DVector(x: 0, y: 0, z: -1),
            up: AVAudio3DVector(x: 0, y: 1, z: 0)
        )
        
        // Set rendering algorithm for best quality
        environment.renderingAlgorithm = .HRTFHQ
        
        // Attach to engine
        engine.attach(environment)
        
        // Connect environment to main mixer
        let mainMixer = engine.mainMixerNode
        engine.connect(environment, to: mainMixer, format: nil)
        
        // Store references
        self.engine = engine
        self.environmentNode = environment
        
        // Start engine
        do {
            try engine.start()
            self.isEngineRunning = true
        } catch {
            throw Error.engineStartFailed(underlying: error)
        }
    }
    

    
    // MARK: - Public API
    
    /// Whether the audio engine is running
    public var isRunning: Bool {
        isEngineRunning
    }
    
    /// Number of active audio sources
    public var sourceCount: Int {
        playerNodes.count
    }
    
    /// Get environment configuration
    public var environmentConfig: (listenerPosition: AVAudio3DPoint, orientation: AVAudio3DVectorOrientation) {
        guard let env = environmentNode else {
            return (AVAudio3DPoint(x: 0, y: 0, z: 0), 
                    AVAudio3DVectorOrientation(
                        forward: AVAudio3DVector(x: 0, y: 0, z: -1),
                        up: AVAudio3DVector(x: 0, y: 1, z: 0)
                    ))
        }
        return (env.listenerPosition, env.listenerVectorOrientation)
    }
    
    /// Create an audio source for a person
    public func createSource(
        for personId: UUID,
        audioBuffer: AVAudioPCMBuffer
    ) throws -> AudioSourceHandle {
        guard let engine = engine, let environment = environmentNode else {
            throw Error.engineStartFailed(underlying: NSError(domain: "SpatialRenderer", code: -1))
        }
        
        let playerNode = AVAudioPlayerNode()
        let mixerNode = AVAudioMixerNode()
        
        // Attach nodes to engine
        engine.attach(playerNode)
        engine.attach(mixerNode)
        
        // Connect: player → mixer → environment
        engine.connect(playerNode, to: mixerNode, format: audioBuffer.format)
        engine.connect(mixerNode, to: environment, format: nil)
        
        // Configure 3D mixing
        mixerNode.sourceMode = .spatializeIfMono
        mixerNode.pointSourceInHeadMode = .bypass
        
        // Store references
        playerNodes[personId] = playerNode
        mixerNodes[personId] = mixerNode
        audioBuffers[personId] = audioBuffer
        
        return AudioSourceHandle(id: UUID(), personId: personId)
    }
    
    /// Create an audio source from file
    public func createSource(
        for personId: UUID,
        audioFile: AVAudioFile
    ) throws -> AudioSourceHandle {
        // Read file into buffer
        let frameCount = AVAudioFrameCount(audioFile.length)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: audioFile.processingFormat,
            frameCapacity: frameCount
        ) else {
            throw Error.bufferCreationFailed
        }
        
        try audioFile.read(into: buffer)
        
        return try createSource(for: personId, audioBuffer: buffer)
    }
    
    /// Remove an audio source
    public func removeSource(for personId: UUID) {
        guard let engine = engine else { return }
        
        if let player = playerNodes[personId] {
            player.stop()
            engine.detach(player)
        }
        
        if let mixer = mixerNodes[personId] {
            engine.detach(mixer)
        }
        
        playerNodes.removeValue(forKey: personId)
        mixerNodes.removeValue(forKey: personId)
        audioBuffers.removeValue(forKey: personId)
        activePositions.removeValue(forKey: personId)
    }
    
    /// Update source position
    public func updatePosition(for personId: UUID, position: SpatialPosition) {
        activePositions[personId] = position
        applyPosition(personId: personId, position: position)
    }
    
    /// Get current source position
    public func sourcePosition(for personId: UUID) -> AVAudio3DPoint? {
        guard let mixer = mixerNodes[personId] else { return nil }
        return mixer.position
    }
    
    /// Get current reverb blend for source
    public func sourceReverbBlend(for personId: UUID) -> Float? {
        guard let mixer = mixerNodes[personId] else { return nil }
        return mixer.reverbBlend
    }
    
    // MARK: - Rendering
    
    /// Render spatial audio for a timeline to output file
    public func render(
        timeline: SpatialAudioTimeline,
        to outputURL: URL,
        format: SpatialAudioFormat = .stereo
    ) async throws {
        guard !playerNodes.isEmpty else {
            throw Error.noSources
        }
        
        // Create output file
        let outputFormat = AVAudioFormat(
            standardFormatWithSampleRate: 48000,
            channels: AVAudioChannelCount(format.channelCount)
        )!
        
        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: outputFormat.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        
        // Process in chunks
        let chunkDuration = 0.1  // 100ms chunks
        let chunks = timeline.chunks(duration: chunkDuration)
        
        for chunk in chunks {
            // Apply positions for this chunk
            for (personId, positions) in chunk.positions {
                if let position = positions.first {
                    updatePosition(for: personId, position: position)
                }
            }
            
            // Render chunk
            let buffer = try await renderChunk(
                duration: chunk.duration,
                format: outputFormat
            )
            
            try outputFile.write(from: buffer)
        }
    }
    
    /// Render a single chunk of audio
    private func renderChunk(
        duration: Double,
        format: AVAudioFormat
    ) async throws -> AVAudioPCMBuffer {
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ) else {
            throw Error.bufferCreationFailed
        }
        
        buffer.frameLength = frameCount
        
        // For now, generate silence - real implementation would capture from engine
        // This is a simplified version; full implementation needs manual render
        if let channelData = buffer.floatChannelData {
            for channel in 0..<Int(format.channelCount) {
                memset(channelData[channel], 0, Int(frameCount) * MemoryLayout<Float>.size)
            }
        }
        
        return buffer
    }
    
    // MARK: - Playback
    
    /// Start playback of all sources
    public func play() {
        for (personId, player) in playerNodes {
            if let buffer = audioBuffers[personId] {
                player.scheduleBuffer(buffer, at: nil, options: .loops)
                player.play()
            }
        }
    }
    
    /// Stop all sources
    public func stop() {
        for player in playerNodes.values {
            player.stop()
        }
    }
    
    /// Pause all sources
    public func pause() {
        for player in playerNodes.values {
            player.pause()
        }
    }
    
    // MARK: - Private Helpers
    
    private func applyPosition(personId: UUID, position: SpatialPosition) {
        guard let mixer = mixerNodes[personId] else { return }
        
        // Convert spherical to Cartesian
        let cartesian = position.toCartesian()
        
        mixer.position = AVAudio3DPoint(
            x: cartesian.x,
            y: cartesian.y,
            z: cartesian.z
        )
        
        // Apply distance-based reverb
        let normalizedDistance = (position.distance - SpatialAudioDefaults.minDistance) /
                                 (SpatialAudioDefaults.maxDistance - SpatialAudioDefaults.minDistance)
        mixer.reverbBlend = min(normalizedDistance * 0.5, 1.0)
    }
    
    /// Clean up resources
    public func cleanup() {
        stop()
        
        for personId in playerNodes.keys {
            removeSource(for: personId)
        }
        
        engine?.stop()
        engine = nil
        environmentNode = nil
        isEngineRunning = false
    }
}

// MARK: - Convenience Extensions

extension AVAudio3DPoint {
    /// Create from SIMD3<Float>
    init(_ simd: SIMD3<Float>) {
        self.init(x: simd.x, y: simd.y, z: simd.z)
    }
}
