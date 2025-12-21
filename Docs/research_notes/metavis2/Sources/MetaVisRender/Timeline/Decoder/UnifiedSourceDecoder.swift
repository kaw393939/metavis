// UnifiedSourceDecoder.swift
// MetaVisRender
//
// Created for Sprint 14: Validation
// Unified decoder supporting both video files and custom frame sources (PDF pages, images, etc.)

import Foundation
import CoreMedia
import Metal

// MARK: - UnifiedSourceDecoder

/// Unified decoder that supports both video files and custom frame sources.
///
/// This wraps MultiSourceDecoder and adds support for custom FrameSource implementations
/// like PDF pages, image sequences, etc.
public actor UnifiedSourceDecoder {
    
    // MARK: - Properties
    
    private let device: MTLDevice
    private let videoDecoder: MultiSourceDecoder
    private var customSources: [String: any FrameSource] = [:]
    
    // MARK: - Initialization
    
    public init(device: MTLDevice, timeline: TimelineModel) {
        self.device = device
        self.videoDecoder = MultiSourceDecoder(device: device, timeline: timeline)
    }
    
    // MARK: - Source Management
    
    /// Registers a custom frame source (PDF page, image sequence, etc.)
    public func registerFrameSource(id: String, source: any FrameSource) {
        customSources[id] = source
    }
    
    /// Registers a video file source
    public func registerVideoSource(id: String, url: URL) async {
        await videoDecoder.registerSource(id: id, url: url)
    }
    
    // MARK: - Frame Decoding
    
    /// Gets a texture from any registered source (video or custom)
    public func texture(source: String, at time: CMTime) async throws -> MTLTexture? {
        // Check if it's a custom source first
        if let customSource = customSources[source] {
            return try await customSource.frame(at: time)
        }
        
        // Otherwise, use the video decoder
        return try await videoDecoder.texture(source: source, at: time)
    }
    
    /// Preloads a source
    public func preload(source: String, at time: CMTime) async throws {
        if let customSource = customSources[source] {
            try await customSource.seek(to: time)
        } else {
            try await videoDecoder.preload(source: source, at: time)
        }
    }
    
    /// Closes all sources
    public func closeAll() async {
        await videoDecoder.closeAll()
        for (_, source) in customSources {
            await source.close()
        }
        customSources.removeAll()
    }
    
    /// Closes a specific source
    public func close(source: String) async {
        if let customSource = customSources.removeValue(forKey: source) {
            await customSource.close()
        } else {
            await videoDecoder.close(source: source)
        }
    }
}
