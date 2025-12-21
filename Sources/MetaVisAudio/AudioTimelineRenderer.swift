import Foundation
import AVFoundation
import Accelerate
import MetaVisCore
import MetaVisTimeline

/// Renders audio from a Timeline using AVAudioEngine in Manual Rendering Mode.
public class AudioTimelineRenderer {
    
    private let engine = AVAudioEngine()
    public let masteringChain = AudioMasteringChain()
    private let graphBuilder = AudioGraphBuilder()
    
    public init() {}

    /// Renders audio as a sequence of smaller buffers.
    /// This avoids rebuilding the engine per chunk and prevents huge allocations for long timelines.
    public func renderChunks(
        timeline: Timeline,
        timeRange: Range<Time>,
        sampleRate: Double = 48000,
        maximumFrameCount: AVAudioFrameCount = 4096,
        reuseChunkBuffer: Bool = false,
        onChunk: (AVAudioPCMBuffer, Time) throws -> Void
    ) async throws {

        let format = try makeStereoFloatFormat(sampleRate: sampleRate)
        let totalFramesDouble = (timeRange.upperBound.seconds - timeRange.lowerBound.seconds) * sampleRate
        let totalFrames = Int64(totalFramesDouble.rounded(.toNearestOrAwayFromZero))
        guard totalFrames > 0 else { return }

        if let request = AudioMixing.dialogCleanwaterV1Request(for: timeline) {
            masteringChain.applyDialogCleanwaterPresetV1(globalGainDB: request.globalGainDB)
        }

        engine.stop()
        engine.reset()

        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: maximumFrameCount)

        let (chainInput, chainOutput) = masteringChain.attach(to: engine, format: format)
        engine.connect(chainOutput, to: engine.mainMixerNode, format: format)
        try await graphBuilder.buildGraph(in: engine, for: timeline, timeRange: timeRange, connectTo: chainInput)

        try engine.start()

        var renderedFrames: Int64 = 0

        // Optional reuse to avoid per-chunk allocations. Only safe when the consumer does not retain the buffer.
        let scratch: AVAudioPCMBuffer? = {
            guard reuseChunkBuffer else { return nil }
            return AVAudioPCMBuffer(pcmFormat: format, frameCapacity: maximumFrameCount)
        }()

        while renderedFrames < totalFrames {
            let remaining = totalFrames - renderedFrames
            let chunkFrames = AVAudioFrameCount(min(Int64(maximumFrameCount), remaining))

            let chunk: AVAudioPCMBuffer
            if let scratch {
                guard scratch.frameCapacity >= chunkFrames else {
                    throw RenderError.allocationFailed
                }
                scratch.frameLength = 0
                chunk = scratch
            } else {
                guard let fresh = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
                    throw RenderError.allocationFailed
                }
                chunk = fresh
            }

            let status = try engine.renderOffline(chunkFrames, to: chunk)

            switch status {
            case .success:
                break
            case .insufficientDataFromInputNode:
                // AVAudioEngine can return 0 frames here if there are no active sources.
                // Force a silent chunk so callers (export) make forward progress deterministically.
                if chunk.frameLength == 0 {
                    chunk.frameLength = chunkFrames
                }
                if let data = chunk.floatChannelData {
                    let channels = Int(chunk.format.channelCount)
                    let frames = Int(chunk.frameLength)
                    for ch in 0..<channels {
                        data[ch].update(repeating: 0, count: frames)
                    }
                }
            case .cannotDoInCurrentContext:
                // Retry once after yielding.
                // Avoid Thread.sleep in async contexts (Swift 6).
                try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
                continue
            case .error:
                throw RenderError.engineFailed
            @unknown default:
                throw RenderError.engineFailed
            }

            applySoftCompressorIfNeeded(chunk, settings: masteringChain.dynamicsSettingsSnapshot())
            applySafetyLimiterIfNeeded(chunk, peakCeiling: 0.98)

            let chunkStartSeconds = timeRange.lowerBound.seconds + (Double(renderedFrames) / sampleRate)
            try onChunk(chunk, Time(seconds: chunkStartSeconds))

            renderedFrames += Int64(chunk.frameLength)
        }

        engine.stop()
    }

    private func applySafetyLimiterIfNeeded(_ buffer: AVAudioPCMBuffer, peakCeiling: Float) {
        guard peakCeiling > 0 else { return }
        guard buffer.frameLength > 0 else { return }
        guard let channelData = buffer.floatChannelData else { return }

        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)

        var peak: Float = 0
        for ch in 0..<channels {
            var channelMax: Float = 0
            vDSP_maxmgv(channelData[ch], 1, &channelMax, vDSP_Length(frames))
            if channelMax > peak {
                peak = channelMax
            }
        }

        guard peak.isFinite, peak > peakCeiling else { return }
        let scale = peakCeiling / peak
        guard scale.isFinite, scale > 0 else { return }

        for ch in 0..<channels {
            var s = scale
            vDSP_vsmul(channelData[ch], 1, &s, channelData[ch], 1, vDSP_Length(frames))
        }
    }

    private func applySoftCompressorIfNeeded(_ buffer: AVAudioPCMBuffer, settings: AudioDynamicsSettings) {
        guard settings.enabled else { return }
        guard settings.ratio.isFinite, settings.ratio >= 1.0 else { return }
        guard settings.thresholdDB.isFinite else { return }

        // Convert dBFS threshold to linear amplitude.
        let threshold = pow(10.0, settings.thresholdDB / 20.0)
        guard threshold.isFinite, threshold > 0 else { return }

        let makeup = pow(10.0, settings.makeupGainDB / 20.0)
        let ratio = settings.ratio

        guard buffer.frameLength > 0 else { return }
        guard let channelData = buffer.floatChannelData else { return }

        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)

        for ch in 0..<channels {
            let ptr = channelData[ch]
            for i in 0..<frames {
                let x = ptr[i]
                let a = abs(x)
                if a <= threshold {
                    ptr[i] = x * makeup
                    continue
                }

                // Hard-knee compression above threshold.
                let over = a - threshold
                let compressed = threshold + (over / ratio)
                let y = (x >= 0 ? compressed : -compressed) * makeup
                ptr[i] = y
            }
        }
    }
    
    /// Renders a chunk of audio for the given time range.
    /// This uses AVAudioEngine's Manual Rendering Mode to pull samples faster (or slower) than real-time.
    public func render(timeline: Timeline, timeRange: Range<Time>, sampleRate: Double = 48000) async throws -> AVAudioPCMBuffer? {
        let format = try makeStereoFloatFormat(sampleRate: sampleRate)
        let totalFramesDouble = (timeRange.upperBound.seconds - timeRange.lowerBound.seconds) * sampleRate
        let totalFrames = AVAudioFrameCount(totalFramesDouble.rounded(.toNearestOrAwayFromZero))

        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else {
            throw RenderError.allocationFailed
        }

        var writeIndex: AVAudioFrameCount = 0
        try await renderChunks(timeline: timeline, timeRange: timeRange, sampleRate: sampleRate, reuseChunkBuffer: true) { chunk, _ in
            guard let dst = output.floatChannelData, let src = chunk.floatChannelData else { return }
            let frames = Int(chunk.frameLength)
            let channels = Int(format.channelCount)
            for ch in 0..<channels {
                dst[ch].advanced(by: Int(writeIndex)).update(from: src[ch], count: frames)
            }
            writeIndex += chunk.frameLength
        }

        output.frameLength = writeIndex
        return output
    }

    private func makeStereoFloatFormat(sampleRate: Double) throws -> AVAudioFormat {
        let channels: AVAudioChannelCount = 2
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels) else {
            throw RenderError.formatCreationFailed(sampleRate: sampleRate, channels: channels)
        }
        return format
    }
}

// Temporary Error stub to avoid module dependency issues if MetaVisPerceptionError isn't available here.
extension AudioTimelineRenderer {
    enum RenderError: Error {
        case allocationFailed
        case engineFailed
        case formatCreationFailed(sampleRate: Double, channels: AVAudioChannelCount)
    }
}
