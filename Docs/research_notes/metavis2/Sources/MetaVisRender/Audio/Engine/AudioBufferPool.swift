// AudioBufferPool.swift
// MetaVisRender
//
// Created for Audio Re-architecture (Phase 1)

import AVFoundation

/// A thread-safe pool for reusing `AVAudioPCMBuffer` instances.
///
/// Allocating buffers during audio processing is expensive and can cause glitches.
/// This pool allows pre-allocating buffers and reusing them.
public actor AudioBufferPool {
    
    // MARK: - Properties
    
    private var pool: [AVAudioFormat: [AVAudioPCMBuffer]] = [:]
    
    public static let shared = AudioBufferPool()
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public API
    
    /// Get a buffer from the pool or create a new one.
    /// - Parameters:
    ///   - format: The audio format.
    ///   - frameCapacity: The required frame capacity.
    /// - Returns: A ready-to-use buffer.
    public func getBuffer(format: AVAudioFormat, frameCapacity: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        if var buffers = pool[format], !buffers.isEmpty {
            // Find a buffer with sufficient capacity
            if let index = buffers.firstIndex(where: { $0.frameCapacity >= frameCapacity }) {
                let buffer = buffers.remove(at: index)
                pool[format] = buffers
                buffer.frameLength = frameCapacity // Reset length
                return buffer
            }
        }
        
        // Create new if none available
        return AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity)
    }
    
    /// Return a buffer to the pool.
    public func returnBuffer(_ buffer: AVAudioPCMBuffer) {
        let format = buffer.format
        var buffers = pool[format] ?? []
        buffers.append(buffer)
        pool[format] = buffers
    }
    
    /// Pre-allocate buffers for a specific format.
    public func preallocate(format: AVAudioFormat, frameCapacity: AVAudioFrameCount, count: Int) {
        var buffers = pool[format] ?? []
        
        for _ in 0..<count {
            if let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) {
                buffers.append(buffer)
            }
        }
        
        pool[format] = buffers
    }
    
    /// Clear the pool.
    public func clear() {
        pool.removeAll()
    }
}
