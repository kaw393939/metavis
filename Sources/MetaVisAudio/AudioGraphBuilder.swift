import Foundation
import AVFoundation
import MetaVisCore
import MetaVisTimeline

/// Responsible for analyzing a Timeline and constructing the AVAudioEngine graph.
public class AudioGraphBuilder {

    private var managedNodes: [AVAudioNode] = []
    
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

        // Detach previously-managed nodes to avoid graph accumulation across renders.
        if !managedNodes.isEmpty {
            for node in managedNodes {
                engine.detach(node)
            }
            managedNodes.removeAll(keepingCapacity: true)
        }
        
        // 1. Clear existing nodes (except mixer/output) if we were doing a full rebuild.
        // For off-line rendering, the engine is usually fresh.
        
        let format: AVAudioFormat
        if engine.isInManualRenderingMode {
            format = engine.manualRenderingFormat
        } else {
            let sampleRate = 48000.0 // Standard Video Audio
            let channels: AVAudioChannelCount = 2
            guard let f = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels) else {
                throw BuildError.formatCreationFailed(sampleRate: sampleRate, channels: channels)
            }
            format = f
        }

        let renderStartSampleIndex = Int64((timeRange.lowerBound.seconds * format.sampleRate).rounded(.toNearestOrAwayFromZero))
        
        for track in timeline.tracks {
            guard track.kind == .audio else { continue }

            // Deterministic topology: each track mixes into its own mixer bus, then into the shared output.
            let trackMixer = AVAudioMixerNode()
            engine.attach(trackMixer)
            engine.connect(trackMixer, to: mixer, format: format)
            managedNodes.append(trackMixer)
            
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
                        engine.connect(sourceNode, to: trackMixer, format: format)
                        managedNodes.append(sourceNode)
                        
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
        let components = URLComponents(string: url.lowercased())
        let host = components?.host ?? ""
        let path = (components?.path ?? "")

        enum ProcKind {
            case sine(freq: Float)
            case whiteNoise
            case pinkNoise
            case sweep(start: Float, end: Float)
            case impulse(intervalSeconds: Double)
        }

        func queryDouble(_ name: String) -> Double? {
            components?.queryItems?.first(where: { $0.name == name })?.value.flatMap(Double.init)
        }

        func kind() -> ProcKind {
            guard host == "audio" else {
                // Back-compat fallback
                return .sine(freq: 1000)
            }

            if path.hasPrefix("/sine") {
                let freq = Float(queryDouble("freq") ?? 1000.0)
                return .sine(freq: freq)
            }

            if path.hasPrefix("/white_noise") || path.hasPrefix("/noise") {
                return .whiteNoise
            }

            if path.hasPrefix("/pink_noise") {
                return .pinkNoise
            }

            if path.hasPrefix("/sweep") {
                let start = Float(queryDouble("start") ?? 20.0)
                let end = Float(queryDouble("end") ?? 20_000.0)
                return .sweep(start: start, end: end)
            }

            if path.hasPrefix("/impulse") {
                let interval = queryDouble("interval") ?? 1.0
                return .impulse(intervalSeconds: max(0.0001, interval))
            }

            // Unknown -> stable default
            return .sine(freq: 1000)
        }

        let procKind = kind()
        
        let sampleRate = format.sampleRate
        let clipStartSampleIndex = Int64((clip.startTime.seconds * sampleRate).rounded(.toNearestOrAwayFromZero))
        let clipEndSampleIndex = Int64(((clip.startTime.seconds + clip.duration.seconds) * sampleRate).rounded(.toNearestOrAwayFromZero))

        let clipOffsetSamples = Int64(max(0.0, clip.offset.seconds) * sampleRate).clampedToInt64()

        let clipSeed: UInt64 = stableSeed64(
            clipName: clip.name,
            sourceFn: clip.asset.sourceFn,
            clipStartSampleIndex: clipStartSampleIndex,
            clipEndSampleIndex: clipEndSampleIndex
        )

        var pinkState = DeterministicPinkNoiseState()

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
                } else {
                    let sourceSampleIndex = (absoluteSampleIndex - clipStartSampleIndex) + clipOffsetSamples
                    let localSeconds = Double(sourceSampleIndex) / sampleRate

                    switch procKind {
                    case let .sine(freq):
                        let phase = (2.0 * Double.pi) * Double(freq) * localSeconds
                        sampleVal = Float(sin(phase)) * 0.1

                    case .whiteNoise:
                        let r = self.deterministicUnitFloat(seed: UInt64(bitPattern: sourceSampleIndex) ^ clipSeed)
                        sampleVal = (r * 2 - 1) * 0.1

                    case .pinkNoise:
                        // Feed deterministic white noise into a deterministic filter state.
                        let r = self.deterministicUnitFloat(seed: UInt64(bitPattern: sourceSampleIndex) ^ clipSeed)
                        let white = (r * 2 - 1)
                        sampleVal = pinkState.next(white: white) * 0.1

                    case let .sweep(start, end):
                        let dur = max(0.0001, clip.duration.seconds)
                        let progress = min(1.0, max(0.0, localSeconds / dur))
                        // Exponential (log) sweep.
                        let startD = max(1e-3, Double(start))
                        let endD = max(1e-3, Double(end))
                        let freq = startD * pow(endD / startD, progress)
                        let phase = (2.0 * Double.pi) * freq * localSeconds
                        sampleVal = Float(sin(phase)) * 0.1

                    case let .impulse(intervalSeconds):
                        let intervalSamples = Int64((intervalSeconds * sampleRate).rounded(.toNearestOrAwayFromZero))
                        if intervalSamples > 0, (sourceSampleIndex % intervalSamples) == 0 {
                            sampleVal = 0.9
                        } else {
                            sampleVal = 0
                        }
                    }
                }

                // Apply deterministic clip envelope (transitions -> gain).
                let timelineSeconds = Double(absoluteSampleIndex) / sampleRate
                let gain = AudioMixing.clipGain(clip: clip, atTimelineSeconds: timelineSeconds)
                let outVal = sampleVal * gain

                if outVal != 0 { anyNonZero = true }
                
                // Write to all channels
                for channelPtr in floatChannelPointers {
                    channelPtr[frame] = outVal
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

private struct DeterministicPinkNoiseState {
    // Classic 7-pole-ish filter bank (inspired by common pink noise implementations).
    // Deterministic given the deterministic white input stream.
    var b0: Float = 0
    var b1: Float = 0
    var b2: Float = 0
    var b3: Float = 0
    var b4: Float = 0
    var b5: Float = 0
    var b6: Float = 0

    mutating func next(white: Float) -> Float {
        b0 = 0.99886 * b0 + white * 0.0555179
        b1 = 0.99332 * b1 + white * 0.0750759
        b2 = 0.96900 * b2 + white * 0.1538520
        b3 = 0.86650 * b3 + white * 0.3104856
        b4 = 0.55000 * b4 + white * 0.5329522
        b5 = -0.7616 * b5 - white * 0.0168980
        let pink = b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362
        b6 = white * 0.115926
        // Rough normalization.
        return pink * 0.11
    }
}

private extension Int64 {
    func clampedToInt64() -> Int64 { self }
}

extension AudioGraphBuilder {
    enum BuildError: Error {
        case formatCreationFailed(sampleRate: Double, channels: AVAudioChannelCount)
    }
}
