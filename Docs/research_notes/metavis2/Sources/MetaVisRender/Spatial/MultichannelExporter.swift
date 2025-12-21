// MultichannelExporter.swift
// MetaVisRender
//
// Created for Sprint 07: Spatial Audio
// Exports spatial audio to multichannel formats (5.1, 7.1, stereo)

import Foundation
import AVFoundation
import Accelerate
import simd

// MARK: - Multichannel Exporter

/// Exports spatial audio to multichannel formats
public actor MultichannelExporter {
    
    // MARK: - Types
    
    public enum Error: Swift.Error {
        case notStarted
        case alreadyStarted
        case unsupportedLayout
        case bufferCreationFailed
        case writeError(underlying: Swift.Error)
    }
    
    // MARK: - Properties
    
    private let format: SpatialAudioFormat
    private let channelRouter: ChannelRouter
    private var outputFile: AVAudioFile?
    private var isExporting = false
    
    // MARK: - Computed Properties
    
    public var channelCount: Int {
        format.channelCount
    }
    
    // MARK: - Initialization
    
    public init(format: SpatialAudioFormat) {
        self.format = format
        self.channelRouter = ChannelRouter(layout: format)
    }
    
    // MARK: - Export API
    
    /// Begin export to file
    public func begin(at url: URL, sampleRate: Double = 48000) throws {
        guard !isExporting else {
            throw Error.alreadyStarted
        }
        
        let audioFormat = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: AVAudioChannelCount(format.channelCount)
        )!
        
        outputFile = try AVAudioFile(
            forWriting: url,
            settings: audioFormat.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        
        isExporting = true
    }
    
    /// Append spatialized audio buffer
    public func append(
        buffer: AVAudioPCMBuffer,
        positions: [UUID: SpatialPosition]
    ) throws {
        guard let outputFile = outputFile, isExporting else {
            throw Error.notStarted
        }
        
        // Route audio to multichannel based on positions
        let routedBuffer = try channelRouter.route(
            buffer: buffer,
            positions: positions
        )
        
        do {
            try outputFile.write(from: routedBuffer)
        } catch {
            throw Error.writeError(underlying: error)
        }
    }
    
    /// Finalize export
    public func finalize() throws {
        outputFile = nil
        isExporting = false
    }
    
    // MARK: - Convenience Methods
    
    /// Export entire spatial timeline
    public func exportTimeline(
        _ timeline: SpatialAudioTimeline,
        audioBuffers: [UUID: AVAudioPCMBuffer],
        to url: URL,
        sampleRate: Double = 48000
    ) async throws {
        try begin(at: url, sampleRate: sampleRate)
        
        // Process chunks
        let chunkDuration = 0.1
        let chunks = timeline.chunks(duration: chunkDuration)
        
        for chunk in chunks {
            // Create a mixed buffer for this chunk
            guard let firstBuffer = audioBuffers.values.first else { continue }
            
            let frameCount = AVAudioFrameCount(chunk.duration * sampleRate)
            guard let mixedBuffer = AVAudioPCMBuffer(
                pcmFormat: firstBuffer.format,
                frameCapacity: frameCount
            ) else {
                throw Error.bufferCreationFailed
            }
            mixedBuffer.frameLength = frameCount
            
            // Average position for this chunk per source
            var chunkPositions: [UUID: SpatialPosition] = [:]
            for (personId, positions) in chunk.positions {
                if let first = positions.first {
                    chunkPositions[personId] = first
                }
            }
            
            try append(buffer: mixedBuffer, positions: chunkPositions)
        }
        
        try finalize()
    }
}

// MARK: - Channel Router

/// Routes audio to appropriate channels based on spatial position
public class ChannelRouter: @unchecked Sendable {
    
    private let layout: SpatialAudioFormat
    
    public init(layout: SpatialAudioFormat) {
        self.layout = layout
    }
    
    /// Route buffer to multichannel output
    public func route(
        buffer: AVAudioPCMBuffer,
        positions: [UUID: SpatialPosition]
    ) throws -> AVAudioPCMBuffer {
        switch layout {
        case .mono:
            return buffer
        case .stereo:
            return try routeToStereo(buffer: buffer, positions: positions)
        case .surround5_1:
            return try routeTo51(buffer: buffer, positions: positions)
        case .surround7_1:
            return try routeTo71(buffer: buffer, positions: positions)
        case .atmos:
            return try routeTo71(buffer: buffer, positions: positions)  // Simplified
        }
    }
    
    // MARK: - Stereo Panning
    
    private func routeToStereo(
        buffer: AVAudioPCMBuffer,
        positions: [UUID: SpatialPosition]
    ) throws -> AVAudioPCMBuffer {
        let outputFormat = AVAudioFormat(
            standardFormatWithSampleRate: buffer.format.sampleRate,
            channels: 2
        )!
        
        guard let output = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: buffer.frameLength
        ) else {
            throw MultichannelExporter.Error.bufferCreationFailed
        }
        output.frameLength = buffer.frameLength
        
        // Calculate average azimuth for pan
        let avgAzimuth: Float
        if positions.isEmpty {
            avgAzimuth = 0
        } else {
            avgAzimuth = positions.values.map(\.azimuth).reduce(0, +) / Float(positions.count)
        }
        
        // Get pan gains
        let gains = panGains(for: SpatialPosition(
            azimuth: avgAzimuth,
            elevation: 0,
            distance: 2,
            time: .zero
        ))
        
        // Apply gains
        applyGains(from: buffer, to: output, gains: gains)
        
        return output
    }
    
    /// Calculate stereo pan gains using equal-power panning
    public func panGains(for position: SpatialPosition) -> [Float] {
        // Convert azimuth (-90 to +90) to pan (-1 to +1)
        let pan = position.azimuth / 90.0
        
        // Equal-power panning
        let leftGain = sqrt(0.5 * (1 - pan))
        let rightGain = sqrt(0.5 * (1 + pan))
        
        return [leftGain, rightGain]
    }
    
    // MARK: - 5.1 Surround
    
    private func routeTo51(
        buffer: AVAudioPCMBuffer,
        positions: [UUID: SpatialPosition]
    ) throws -> AVAudioPCMBuffer {
        let outputFormat = AVAudioFormat(
            standardFormatWithSampleRate: buffer.format.sampleRate,
            channels: 6
        )!
        
        guard let output = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: buffer.frameLength
        ) else {
            throw MultichannelExporter.Error.bufferCreationFailed
        }
        output.frameLength = buffer.frameLength
        
        // Initialize output to zeros
        if let channelData = output.floatChannelData {
            for channel in 0..<6 {
                memset(channelData[channel], 0, Int(buffer.frameLength) * MemoryLayout<Float>.size)
            }
        }
        
        // Apply VBAP for each source
        for (_, position) in positions {
            let gains = vbapGains(for: position)
            addWithGains(from: buffer, to: output, gains: gains)
        }
        
        // If no positions, use center panning
        if positions.isEmpty {
            let gains = vbapGains(for: SpatialPosition(azimuth: 0, elevation: 0, distance: 2, time: .zero))
            addWithGains(from: buffer, to: output, gains: gains)
        }
        
        return output
    }
    
    /// Vector Base Amplitude Panning for 5.1
    public func vbapGains(for position: SpatialPosition) -> [Float] {
        let azimuth = position.azimuth
        
        // Speaker positions (degrees from center):
        // L: -30°, R: +30°, C: 0°, Ls: -110°, Rs: +110°
        // Channel order: L, R, C, LFE, Ls, Rs
        
        var gains = [Float](repeating: 0, count: 6)
        
        // Front arc: -30° to +30°
        if azimuth >= -30 && azimuth <= 30 {
            if azimuth < 0 {
                // Left-center blend
                let t = (azimuth + 30) / 30.0  // 0 at L, 1 at C
                gains[0] = 1 - t              // L
                gains[2] = t                  // C
            } else {
                // Right-center blend
                let t = azimuth / 30.0        // 0 at C, 1 at R
                gains[2] = 1 - t              // C
                gains[1] = t                  // R
            }
        }
        // Left side: -110° to -30°
        else if azimuth < -30 && azimuth >= -110 {
            let t = (azimuth + 30) / -80.0    // 0 at L, 1 at Ls
            gains[0] = 1 - t                  // L
            gains[4] = t                      // Ls
        }
        // Right side: +30° to +110°
        else if azimuth > 30 && azimuth <= 110 {
            let t = (azimuth - 30) / 80.0     // 0 at R, 1 at Rs
            gains[1] = 1 - t                  // R
            gains[5] = t                      // Rs
        }
        // Rear left: beyond -110°
        else if azimuth < -110 {
            gains[4] = 1.0                    // Ls
        }
        // Rear right: beyond +110°
        else if azimuth > 110 {
            gains[5] = 1.0                    // Rs
        }
        
        // Add some LFE based on distance (farther = more room)
        gains[3] = min(position.distance / 10.0, 0.3) * 0.5
        
        // Normalize to preserve energy
        let sum = gains.reduce(0, +)
        if sum > 0 {
            return gains.map { $0 / sum }
        }
        
        return gains
    }
    
    // MARK: - 7.1 Surround
    
    private func routeTo71(
        buffer: AVAudioPCMBuffer,
        positions: [UUID: SpatialPosition]
    ) throws -> AVAudioPCMBuffer {
        let outputFormat = AVAudioFormat(
            standardFormatWithSampleRate: buffer.format.sampleRate,
            channels: 8
        )!
        
        guard let output = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: buffer.frameLength
        ) else {
            throw MultichannelExporter.Error.bufferCreationFailed
        }
        output.frameLength = buffer.frameLength
        
        // Initialize output to zeros
        if let channelData = output.floatChannelData {
            for channel in 0..<8 {
                memset(channelData[channel], 0, Int(buffer.frameLength) * MemoryLayout<Float>.size)
            }
        }
        
        // Apply VBAP for each source
        for (_, position) in positions {
            let gains = vbap71Gains(for: position)
            addWithGains(from: buffer, to: output, gains: gains)
        }
        
        // If no positions, use center panning
        if positions.isEmpty {
            let gains = vbap71Gains(for: SpatialPosition(azimuth: 0, elevation: 0, distance: 2, time: .zero))
            addWithGains(from: buffer, to: output, gains: gains)
        }
        
        return output
    }
    
    /// VBAP for 7.1
    private func vbap71Gains(for position: SpatialPosition) -> [Float] {
        let azimuth = position.azimuth
        
        // Channel order: L, R, C, LFE, Ls, Rs, Lss, Rss
        // Positions: L:-30, R:+30, C:0, Ls:-135, Rs:+135, Lss:-90, Rss:+90
        
        var gains = [Float](repeating: 0, count: 8)
        
        // Front arc: -30° to +30°
        if azimuth >= -30 && azimuth <= 30 {
            if azimuth < 0 {
                let t = (azimuth + 30) / 30.0
                gains[0] = 1 - t              // L
                gains[2] = t                  // C
            } else {
                let t = azimuth / 30.0
                gains[2] = 1 - t              // C
                gains[1] = t                  // R
            }
        }
        // Left-front to left-side: -30° to -90°
        else if azimuth < -30 && azimuth >= -90 {
            let t = (azimuth + 30) / -60.0
            gains[0] = 1 - t                  // L
            gains[6] = t                      // Lss
        }
        // Left-side to left-surround: -90° to -135°
        else if azimuth < -90 && azimuth >= -135 {
            let t = (azimuth + 90) / -45.0
            gains[6] = 1 - t                  // Lss
            gains[4] = t                      // Ls
        }
        // Right-front to right-side: +30° to +90°
        else if azimuth > 30 && azimuth <= 90 {
            let t = (azimuth - 30) / 60.0
            gains[1] = 1 - t                  // R
            gains[7] = t                      // Rss
        }
        // Right-side to right-surround: +90° to +135°
        else if azimuth > 90 && azimuth <= 135 {
            let t = (azimuth - 90) / 45.0
            gains[7] = 1 - t                  // Rss
            gains[5] = t                      // Rs
        }
        // Rear
        else if azimuth < -135 {
            gains[4] = 1.0                    // Ls
        } else if azimuth > 135 {
            gains[5] = 1.0                    // Rs
        }
        
        // LFE
        gains[3] = min(position.distance / 10.0, 0.3) * 0.5
        
        // Normalize
        let sum = gains.reduce(0, +)
        if sum > 0 {
            return gains.map { $0 / sum }
        }
        
        return gains
    }
    
    // MARK: - Helpers
    
    private func applyGains(
        from source: AVAudioPCMBuffer,
        to dest: AVAudioPCMBuffer,
        gains: [Float]
    ) {
        guard let sourceData = source.floatChannelData,
              let destData = dest.floatChannelData else { return }
        
        let frameCount = Int(min(source.frameLength, dest.frameLength))
        let destChannels = Int(dest.format.channelCount)
        let sourceChannels = Int(source.format.channelCount)
        
        for destChannel in 0..<min(destChannels, gains.count) {
            let gain = gains[destChannel]
            guard gain > 0 else { continue }
            
            // Sum from all source channels
            for srcChannel in 0..<sourceChannels {
                vDSP_vsma(
                    sourceData[srcChannel], 1,
                    [gain],
                    destData[destChannel], 1,
                    destData[destChannel], 1,
                    vDSP_Length(frameCount)
                )
            }
        }
    }
    
    private func addWithGains(
        from source: AVAudioPCMBuffer,
        to dest: AVAudioPCMBuffer,
        gains: [Float]
    ) {
        guard let sourceData = source.floatChannelData,
              let destData = dest.floatChannelData else { return }
        
        let frameCount = Int(min(source.frameLength, dest.frameLength))
        let destChannels = Int(dest.format.channelCount)
        let sourceChannels = Int(source.format.channelCount)
        
        for destChannel in 0..<min(destChannels, gains.count) {
            let gain = gains[destChannel]
            guard gain > 0 else { continue }
            
            // Add to existing with gain
            for srcChannel in 0..<sourceChannels {
                vDSP_vsma(
                    sourceData[srcChannel], 1,
                    [gain],
                    destData[destChannel], 1,
                    destData[destChannel], 1,
                    vDSP_Length(frameCount)
                )
            }
        }
    }
}
