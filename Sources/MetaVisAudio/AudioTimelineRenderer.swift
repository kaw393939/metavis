import Foundation
import AVFoundation
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
    ) throws {

        let format = try makeStereoFloatFormat(sampleRate: sampleRate)
        let totalFramesDouble = (timeRange.upperBound.seconds - timeRange.lowerBound.seconds) * sampleRate
        let totalFrames = Int64(totalFramesDouble.rounded(.toNearestOrAwayFromZero))
        guard totalFrames > 0 else { return }

        if AudioMixing.timelineRequestsDialogCleanwaterV1(timeline) {
            masteringChain.applyDialogCleanwaterPresetV1()
        }

        engine.stop()
        engine.reset()

        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: maximumFrameCount)

        let (chainInput, chainOutput) = masteringChain.attach(to: engine, format: format)
        engine.connect(chainOutput, to: engine.mainMixerNode, format: format)
        try graphBuilder.buildGraph(in: engine, for: timeline, timeRange: timeRange, connectTo: chainInput)

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
            case .success, .insufficientDataFromInputNode:
                break
            case .cannotDoInCurrentContext:
                // Retry once after yielding.
                Thread.sleep(forTimeInterval: 0.001)
                continue
            case .error:
                throw RenderError.engineFailed
            @unknown default:
                throw RenderError.engineFailed
            }

            let chunkStartSeconds = timeRange.lowerBound.seconds + (Double(renderedFrames) / sampleRate)
            try onChunk(chunk, Time(seconds: chunkStartSeconds))

            renderedFrames += Int64(chunk.frameLength)
        }

        engine.stop()
    }
    
    /// Renders a chunk of audio for the given time range.
    /// This uses AVAudioEngine's Manual Rendering Mode to pull samples faster (or slower) than real-time.
    public func render(timeline: Timeline, timeRange: Range<Time>, sampleRate: Double = 48000) throws -> AVAudioPCMBuffer? {
        let format = try makeStereoFloatFormat(sampleRate: sampleRate)
        let totalFramesDouble = (timeRange.upperBound.seconds - timeRange.lowerBound.seconds) * sampleRate
        let totalFrames = AVAudioFrameCount(totalFramesDouble.rounded(.toNearestOrAwayFromZero))

        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else {
            throw RenderError.allocationFailed
        }

        var writeIndex: AVAudioFrameCount = 0
        try renderChunks(timeline: timeline, timeRange: timeRange, sampleRate: sampleRate, reuseChunkBuffer: true) { chunk, _ in
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
