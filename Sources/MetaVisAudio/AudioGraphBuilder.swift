import Foundation
import AVFoundation
import MetaVisCore
import MetaVisTimeline

/// Responsible for analyzing a Timeline and constructing the AVAudioEngine graph.
public class AudioGraphBuilder {
    
    public init() {}
    
    /// Rebuilds the graph for the given timeline and time range.
    /// - Parameters:
    ///   - engine: The audio engine to populate.
    ///   - timeline: The edit timeline.
    ///   - timeRange: The range we are playing/rendering.
    ///   - mixer: The main mixer node to connect sources to.
    public func buildGraph(
        in engine: AVAudioEngine,
        for timeline: Timeline,
        timeRange: Range<Time>,
        connectTo mixer: AVAudioNode // output of the builder
    ) throws {
        
        // 1. Clear existing nodes (except mixer/output) if we were doing a full rebuild.
        // For off-line rendering, the engine is usually fresh.
        
        let format: AVAudioFormat
        if engine.isInManualRenderingMode {
            format = engine.manualRenderingFormat
        } else {
            let sampleRate = 48000.0 // Standard Video Audio
            format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        }

        let renderStartSampleIndex = Int64((timeRange.lowerBound.seconds * format.sampleRate).rounded(.toNearestOrAwayFromZero))
        
        for track in timeline.tracks {
            guard track.kind == .audio else { continue }
            
            for clip in track.clips {
                // Overlap Check
                let clipStart = clip.startTime.seconds
                let clipEnd = clipStart + clip.duration.seconds
                let rangeStart = timeRange.lowerBound.seconds
                let rangeEnd = timeRange.upperBound.seconds
                
                if clipEnd > rangeStart && clipStart < rangeEnd {
                    
                    // Creates a source node for this clip
                    if let sourceNode = createSourceNode(for: clip, format: format, renderStartSampleIndex: renderStartSampleIndex) {
                        engine.attach(sourceNode)
                        engine.connect(sourceNode, to: mixer, format: format)
                        
                        // Schedule Playback?
                        // For offline manual rendering, source nodes (procedural) are pulled.
                        // For player nodes (file), we need to schedule segments.
                        
                        // NOTE: For Phase 1, we are focusing on procedural "God Test" signals
                        // which use AVAudioSourceNode (pull-based). Files would need AVAudioPlayerNode.
                    }
                }
            }
        }
    }
    
    private func createSourceNode(for clip: Clip, format: AVAudioFormat, renderStartSampleIndex: Int64) -> AVAudioNode? {
        let url = clip.asset.sourceFn
        
        if url.lowercased().hasPrefix("ligm://") {
            return createProceduralNode(url: url, clip: clip, format: format, renderStartSampleIndex: renderStartSampleIndex)
        } else {
            // File playback stub
            // In a real app, this would open the file, create AVAudioPlayerNode, scheduleSegment.
            return nil 
        }
    }
    
    private func createProceduralNode(url: String, clip: Clip, format: AVAudioFormat, renderStartSampleIndex: Int64) -> AVAudioNode {
        // Parse URL params
        var frequency: Float = 1000.0
        var isNoise = false
        
        let components = URLComponents(string: url.lowercased())
        let path = (components?.host ?? "") + (components?.path ?? "")
        
        if path.contains("sine") {
            if let freqVal = components?.queryItems?.first(where: { $0.name == "freq" })?.value.flatMap(Double.init) {
                frequency = Float(freqVal)
            }
        } else if path.contains("noise") {
            isNoise = true
        }
        
        let sampleRate = format.sampleRate
        let clipStartSampleIndex = Int64((clip.startTime.seconds * sampleRate).rounded(.toNearestOrAwayFromZero))
        let clipEndSampleIndex = Int64(((clip.startTime.seconds + clip.duration.seconds) * sampleRate).rounded(.toNearestOrAwayFromZero))

        let clipSeed: UInt64 = stableSeed64(
            clipName: clip.name,
            sourceFn: clip.asset.sourceFn,
            clipStartSampleIndex: clipStartSampleIndex,
            clipEndSampleIndex: clipEndSampleIndex
        )

        return AVAudioSourceNode(format: format) { isSilence, timestamp, frameCount, outputData -> OSStatus in
            let channels = UnsafeMutableAudioBufferListPointer(outputData)
            let frames = Int(frameCount)
            
            // Pre-bind pointers outside the loop (Performance + Safety)
            var floatChannelPointers: [UnsafeMutablePointer<Float>] = []
            for channel in 0..<channels.count {
                if let rawPtr = channels[channel].mData {
                    // Use assumingMemoryBound since AVFoundation provides Float buffer for this format
                    floatChannelPointers.append(rawPtr.assumingMemoryBound(to: Float.self))
                }
            }
            
            let renderSampleTimeIndex = Int64(timestamp.pointee.mSampleTime)
            var anyNonZero = false

            for frame in 0..<frames {
                let absoluteSampleIndex = renderStartSampleIndex + renderSampleTimeIndex + Int64(frame)
                let sampleVal: Float

                if absoluteSampleIndex < clipStartSampleIndex || absoluteSampleIndex >= clipEndSampleIndex {
                    sampleVal = 0
                } else if isNoise {
                    let r = self.deterministicUnitFloat(seed: UInt64(bitPattern: absoluteSampleIndex) ^ clipSeed)
                    sampleVal = (r * 2 - 1) * 0.1
                } else {
                    let localSampleIndex = absoluteSampleIndex - clipStartSampleIndex
                    let localSeconds = Double(localSampleIndex) / sampleRate
                    let phase = (2.0 * Double.pi) * Double(frequency) * localSeconds
                    sampleVal = Float(sin(phase)) * 0.1
                }

                if sampleVal != 0 { anyNonZero = true }
                
                // Write to all channels
                for channelPtr in floatChannelPointers {
                    channelPtr[frame] = sampleVal
                }
            }
            
            isSilence.pointee = ObjCBool(!anyNonZero)
            return noErr
        }
    }

    private func deterministicUnitFloat(seed: UInt64) -> Float {
        // SplitMix64 -> [0, 1)
        var z = seed &+ 0x9E3779B97F4A7C15
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z = z ^ (z >> 31)
        let mantissa = z >> 40
        return Float(mantissa) / Float(1 << 24)
    }

    private func stableSeed64(
        clipName: String,
        sourceFn: String,
        clipStartSampleIndex: Int64,
        clipEndSampleIndex: Int64
    ) -> UInt64 {
        var h: UInt64 = 14695981039346656037
        func mixBytes(_ bytes: [UInt8]) {
            for b in bytes {
                h ^= UInt64(b)
                h &*= 1099511628211
            }
        }

        mixBytes(Array(clipName.utf8))
        mixBytes([0])
        mixBytes(Array(sourceFn.utf8))
        mixBytes([0])
        mixBytes(withUnsafeBytes(of: clipStartSampleIndex.littleEndian, Array.init))
        mixBytes(withUnsafeBytes(of: clipEndSampleIndex.littleEndian, Array.init))
        return h
    }
}
