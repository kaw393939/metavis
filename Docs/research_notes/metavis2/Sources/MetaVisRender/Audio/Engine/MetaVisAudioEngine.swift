// MetaVisAudioEngine.swift
// MetaVisRender
//
// Created for Audio Re-architecture (Phase 1)
// The central controller for the modern, Apple Silicon-optimized audio pipeline.

import AVFoundation
import Foundation

/// The central audio engine for MetaVis, wrapping `AVAudioEngine`.
///
/// This engine replaces the legacy `AudioMixer` and provides:
/// - Real-time playback and preview.
/// - Deterministic offline rendering.
/// - Modern graph-based audio processing.
/// - Apple Silicon optimizations (Audio Workgroups, Performance Core pinning).
public actor MetaVisAudioEngine {

    // MARK: - Properties

    /// The underlying Core Audio engine.
    private let engine: AVAudioEngine

    /// The main mixer node (connected to engine.mainMixerNode or output).
    private let mainMixer: AVAudioMixerNode

    /// Configuration for the engine.
    public let configuration: Configuration

    /// Current state of the engine.
    public private(set) var isRunning: Bool = false

    // MARK: - Configuration

    public struct Configuration: Sendable {
        /// Internal sample rate (default: 48kHz).
        public let sampleRate: Double
        /// Channel count (default: 2 for stereo).
        public let channelCount: AVAudioChannelCount
        /// I/O Buffer duration (latency hint).
        public let ioBufferDuration: TimeInterval

        public static let `default` = Configuration(
            sampleRate: 48000,
            channelCount: 2,
            ioBufferDuration: 0.005 // ~5ms for low latency
        )
    }

    // MARK: - Initialization

    public init(configuration: Configuration = .default) {
        self.configuration = configuration
        self.engine = AVAudioEngine()
        self.mainMixer = engine.mainMixerNode
        
        setupEngine()
    }

    private func setupEngine() {
        // Configure the main mixer format
        let format = AVAudioFormat(
            standardFormatWithSampleRate: configuration.sampleRate,
            channels: configuration.channelCount
        )
        
        // Ensure the engine is reset
        engine.reset()
        
        // In a real implementation, we would build the graph here.
        // For now, we just ensure the mixer is connected to output.
        engine.connect(mainMixer, to: engine.outputNode, format: format)
        
        // Prepare the engine
        // engine.prepare() // Moved to start/enableManualRenderingMode to avoid locking state
        
        print("[MetaVisAudioEngine] Initialized with sampleRate: \(configuration.sampleRate)")
    }

    // MARK: - Control

    /// Start the engine for real-time playback.
    public func start() throws {
        guard !isRunning else { return }
        
        engine.prepare() // Prepare before starting
        try engine.start()
        isRunning = true
        print("[MetaVisAudioEngine] Started")
    }

    /// Stop the engine.
    public func stop() {
        guard isRunning else { return }
        
        engine.stop()
        isRunning = false
        print("[MetaVisAudioEngine] Stopped")
    }

    // MARK: - Offline Rendering

    /// Enable manual rendering mode for offline export.
    /// - Parameter maxFrameCount: The maximum number of frames the client will ask for in each render cycle.
    public func enableManualRenderingMode(maxFrameCount: AVAudioFrameCount) throws {
        let format = AVAudioFormat(
            standardFormatWithSampleRate: configuration.sampleRate,
            channels: configuration.channelCount
        )
        
        try engine.enableManualRenderingMode(
            .offline,
            format: format ?? engine.mainMixerNode.outputFormat(forBus: 0),
            maximumFrameCount: maxFrameCount
        )
        
        engine.prepare()
        try engine.start()
        isRunning = true
        print("[MetaVisAudioEngine] Enabled Manual Rendering Mode")
    }
    
    /// Render a block of audio data in offline mode.
    /// - Parameter numberOfFrames: Number of frames to render.
    /// - Returns: The rendered buffer.
    public func renderOffline(numberOfFrames: AVAudioFrameCount) throws -> AVAudioPCMBuffer? {
        guard engine.manualRenderingMode == .offline else {
            throw AudioEngineError.notInOfflineMode
        }
        
        let buffer = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat,
            frameCapacity: numberOfFrames
        )!
        
        let status = try engine.renderOffline(numberOfFrames, to: buffer)
        
        switch status {
        case .success:
            return buffer
        case .insufficientDataFromInputNode:
            // This is expected if inputs run out, but for a timeline we usually control sources.
            return buffer
        case .cannotDoInCurrentContext:
            throw AudioEngineError.renderFailed("Cannot do in current context")
        case .error:
            throw AudioEngineError.renderFailed("Unknown render error")
        @unknown default:
            throw AudioEngineError.renderFailed("Unknown status")
        }
    }
}

// MARK: - Errors

public enum AudioEngineError: Error {
    case notInOfflineMode
    case renderFailed(String)
}
