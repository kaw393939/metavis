import Foundation
import AVFoundation
import CoreMedia
import MetaVisCore
import MetaVisTimeline

/// Responsible for analyzing a Timeline and constructing the AVAudioEngine graph.
public class AudioGraphBuilder {

    private var managedNodes: [AVAudioNode] = []
    private var activeStreams: [FileClipStream] = []
    
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
    ) async throws {

        // Detach previously-managed nodes to avoid graph accumulation across renders.
        if !managedNodes.isEmpty {
            for node in managedNodes {
                engine.detach(node)
            }
            managedNodes.removeAll(keepingCapacity: true)
        }

        // Cancel any active file streams from a previous graph build.
        if !activeStreams.isEmpty {
            for s in activeStreams {
                s.cancel()
            }
            activeStreams.removeAll(keepingCapacity: true)
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
        let maxFramesPerRenderCall: Int = {
            if engine.isInManualRenderingMode {
                return Int(engine.manualRenderingMaximumFrameCount)
            }
            // Conservative default for realtime graphs.
            return 4096
        }()
        
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
                    if let sourceNode = try await createSourceNode(
                        for: clip,
                        format: format,
                        renderStartSampleIndex: renderStartSampleIndex,
                        timeRange: timeRange,
                        maxFramesPerRenderCall: maxFramesPerRenderCall
                    ) {
                        engine.attach(sourceNode)
                        engine.connect(sourceNode, to: trackMixer, format: format)
                        managedNodes.append(sourceNode)
                    }
                }
            }
        }
    }
    
    private func createSourceNode(
        for clip: Clip,
        format: AVAudioFormat,
        renderStartSampleIndex: Int64,
        timeRange: Range<Time>,
        maxFramesPerRenderCall: Int
    ) async throws -> AVAudioNode? {
        let sourceFn = clip.asset.sourceFn

        if sourceFn.lowercased().hasPrefix("ligm://") {
            return createProceduralNode(url: sourceFn, clip: clip, format: format, renderStartSampleIndex: renderStartSampleIndex)
        }

        return try await createFileNode(
            sourceFn: sourceFn,
            clip: clip,
            format: format,
            renderStartSampleIndex: renderStartSampleIndex,
            timeRange: timeRange,
            maxFramesPerRenderCall: maxFramesPerRenderCall
        )
    }

    private func createFileNode(
        sourceFn: String,
        clip: Clip,
        format: AVAudioFormat,
        renderStartSampleIndex: Int64,
        timeRange: Range<Time>,
        maxFramesPerRenderCall: Int
    ) async throws -> AVAudioNode? {
        guard let url = resolveFileURL(from: sourceFn) else {
            return nil
        }

        // Compute overlap between clip and requested render timeRange.
        let clipStartSeconds = clip.startTime.seconds
        let clipEndSeconds = clipStartSeconds + clip.duration.seconds
        let overlapStart = max(timeRange.lowerBound.seconds, clipStartSeconds)
        let overlapEnd = min(timeRange.upperBound.seconds, clipEndSeconds)
        guard overlapEnd > overlapStart else {
            return nil
        }

        let sampleRate = format.sampleRate
        let activeStartSampleIndex = Int64((overlapStart * sampleRate).rounded(.toNearestOrAwayFromZero))
        let activeEndSampleIndex = Int64((overlapEnd * sampleRate).rounded(.toNearestOrAwayFromZero))
        let activeFramesTotal = max(0, Int(activeEndSampleIndex - activeStartSampleIndex))
        guard activeFramesTotal > 0 else {
            return nil
        }

        let startInClipSeconds = overlapStart - clipStartSeconds
        let sourceStartSeconds = max(0.0, clip.offset.seconds) + max(0.0, startInClipSeconds)

        // Stream only what we need for this render timeRange.
        let stream = try await FileClipStream.make(
            url: url,
            targetSampleRate: sampleRate,
            targetChannels: Int(format.channelCount),
            startSeconds: sourceStartSeconds,
            durationSeconds: overlapEnd - overlapStart,
            maxFramesPerRenderCall: maxFramesPerRenderCall
        )
        activeStreams.append(stream)

        // Scratch buffer (interleaved) reused across render callbacks.
        // Sized to the engine's expected maximum callback quantum.
        let outChannels = max(1, Int(format.channelCount))
        let scratchCapacityFrames = max(1, maxFramesPerRenderCall)
        var scratch = [Float](repeating: 0, count: scratchCapacityFrames * outChannels)

        return AVAudioSourceNode(format: format) { isSilence, timestamp, frameCount, outputData -> OSStatus in
            let channels = UnsafeMutableAudioBufferListPointer(outputData)
            let frames = Int(frameCount)

            var floatChannelPointers: [UnsafeMutablePointer<Float>] = []
            floatChannelPointers.reserveCapacity(channels.count)
            for channel in 0..<channels.count {
                if let rawPtr = channels[channel].mData {
                    floatChannelPointers.append(rawPtr.assumingMemoryBound(to: Float.self))
                }
            }

            let renderSampleTimeIndex = Int64(timestamp.pointee.mSampleTime)
            var anyNonZero = false

            // Determine how much of this callback falls within the active clip region.
            let callbackStartSampleIndex = renderStartSampleIndex + renderSampleTimeIndex
            let activeStartInCallback = max(0, Int(activeStartSampleIndex - callbackStartSampleIndex))
            let activeEndInCallback = min(frames, Int(activeEndSampleIndex - callbackStartSampleIndex))

            // Prefix silence.
            if activeStartInCallback > 0 {
                for i in 0..<activeStartInCallback {
                    for channelPtr in floatChannelPointers {
                        channelPtr[i] = 0
                    }
                }
            }

            // Active region: pull frames in one batch.
            let activeFramesRequested = max(0, activeEndInCallback - activeStartInCallback)
            let activeFrames = min(activeFramesRequested, scratchCapacityFrames)
            if activeFramesRequested > scratchCapacityFrames {
                // Safety: the engine requested a larger quantum than our precomputed max.
                // We clamp to avoid any out-of-bounds writes into the scratch buffer.
                // The overflow region will be rendered as silence.
            }

            if activeFrames > 0 {
                let ok = scratch.withUnsafeMutableBufferPointer { dst in
                    stream.readInterleavedFramesBlocking(frameCount: activeFrames, into: dst.baseAddress!, channels: outChannels)
                }

                if ok {
                    for i in 0..<activeFrames {
                        let absoluteSampleIndex = callbackStartSampleIndex + Int64(activeStartInCallback + i)
                        let timelineSeconds = Double(absoluteSampleIndex) / sampleRate
                        let gain = AudioMixing.clipGain(clip: clip, atTimelineSeconds: timelineSeconds)

                        let base = i * outChannels
                        for ch in 0..<outChannels {
                            let v = scratch[base + ch] * gain
                            floatChannelPointers[ch][activeStartInCallback + i] = v
                            if v != 0 { anyNonZero = true }
                        }
                    }
                } else {
                    // If we fail to read (end-of-stream), output silence for the active region.
                    for i in activeStartInCallback..<(activeStartInCallback + activeFrames) {
                        for channelPtr in floatChannelPointers {
                            channelPtr[i] = 0
                        }
                    }
                }
            }

            // If we clamped the active region, silence the remainder.
            if activeFramesRequested > activeFrames {
                let start = activeStartInCallback + activeFrames
                let end = min(activeEndInCallback, activeStartInCallback + activeFramesRequested)
                if start < end {
                    for i in start..<end {
                        for channelPtr in floatChannelPointers {
                            channelPtr[i] = 0
                        }
                    }
                }
            }

            // Suffix silence.
            if activeEndInCallback < frames {
                for i in activeEndInCallback..<frames {
                    for channelPtr in floatChannelPointers {
                        channelPtr[i] = 0
                    }
                }
            }

            isSilence.pointee = ObjCBool(!anyNonZero)
            return noErr
        }
    }

    private func resolveFileURL(from sourceFn: String) -> URL? {
        if let url = URL(string: sourceFn), url.scheme == "file" {
            return url
        }

        if sourceFn.hasPrefix("/") {
            return URL(fileURLWithPath: sourceFn)
        }

        // Treat as workspace-relative / CWD-relative path.
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        return URL(fileURLWithPath: sourceFn, relativeTo: cwd)
    }

    // File decoding is handled by `FileClipStream` to avoid loading the entire track into memory.
    
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
            case marker(atSeconds: Double)
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

            if path.hasPrefix("/marker") {
                let at = queryDouble("at") ?? 0.0
                return .marker(atSeconds: max(0.0, at))
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

                    case let .marker(atSeconds):
                        let targetSampleIndex = Int64((atSeconds * sampleRate).rounded(.toNearestOrAwayFromZero))
                        if sourceSampleIndex == targetSampleIndex {
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

// MARK: - Streaming file-backed audio (bounded memory)

private final class FileClipStream: @unchecked Sendable {
    private final class RingBuffer {
        private let condition = NSCondition()
        private var storage: [Float]
        let channels: Int
        private let capacityFrames: Int

        private var readFrameIndex: Int = 0
        private var writeFrameIndex: Int = 0
        private var availableFrames: Int = 0
        private var finished: Bool = false
        private var cancelled: Bool = false

        init(capacityFrames: Int, channels: Int) {
            self.capacityFrames = max(1, capacityFrames)
            self.channels = max(1, channels)
            self.storage = [Float](repeating: 0, count: self.capacityFrames * self.channels)
        }

        func cancel() {
            condition.lock()
            cancelled = true
            condition.broadcast()
            condition.unlock()
        }

        func markFinished() {
            condition.lock()
            finished = true
            condition.broadcast()
            condition.unlock()
        }

        func writeInterleaved(_ src: UnsafeBufferPointer<Float>, frameCount: Int) {
            guard frameCount > 0 else { return }
            let framesToWrite = frameCount

            condition.lock()
            defer { condition.unlock() }

            var remaining = framesToWrite
            var srcFrameIndex = 0

            while remaining > 0 {
                while !cancelled && availableFrames >= capacityFrames {
                    condition.wait()
                }
                if cancelled { return }

                let writableFrames = min(remaining, capacityFrames - availableFrames)
                if writableFrames <= 0 { continue }

                let firstChunk = min(writableFrames, capacityFrames - writeFrameIndex)
                let secondChunk = writableFrames - firstChunk

                // Copy first chunk.
                if firstChunk > 0 {
                    let dstBase = (writeFrameIndex * channels)
                    let srcBase = (srcFrameIndex * channels)
                    storage.withUnsafeMutableBufferPointer { dst in
                        dst.baseAddress!.advanced(by: dstBase).update(from: src.baseAddress!.advanced(by: srcBase), count: firstChunk * channels)
                    }
                    writeFrameIndex = (writeFrameIndex + firstChunk) % capacityFrames
                    availableFrames += firstChunk
                    remaining -= firstChunk
                    srcFrameIndex += firstChunk
                }

                // Copy second chunk (wrap).
                if secondChunk > 0 {
                    let dstBase = (writeFrameIndex * channels)
                    let srcBase = (srcFrameIndex * channels)
                    storage.withUnsafeMutableBufferPointer { dst in
                        dst.baseAddress!.advanced(by: dstBase).update(from: src.baseAddress!.advanced(by: srcBase), count: secondChunk * channels)
                    }
                    writeFrameIndex = (writeFrameIndex + secondChunk) % capacityFrames
                    availableFrames += secondChunk
                    remaining -= secondChunk
                    srcFrameIndex += secondChunk
                }

                condition.signal()
            }
        }

        func readInterleavedBlocking(into dst: UnsafeMutablePointer<Float>, frameCount: Int) -> Bool {
            guard frameCount > 0 else { return true }

            condition.lock()
            defer { condition.unlock() }

            // Wait until we have enough frames or we are finished/cancelled.
            while !cancelled && availableFrames < frameCount && !finished {
                condition.wait()
            }
            if cancelled { return false }

            let framesToRead = min(frameCount, availableFrames)
            if framesToRead <= 0 {
                // Finished or empty.
                return false
            }

            let firstChunk = min(framesToRead, capacityFrames - readFrameIndex)
            let secondChunk = framesToRead - firstChunk

            // Copy first chunk.
            if firstChunk > 0 {
                let srcBase = readFrameIndex * channels
                storage.withUnsafeBufferPointer { src in
                    dst.advanced(by: 0).update(from: src.baseAddress!.advanced(by: srcBase), count: firstChunk * channels)
                }
                readFrameIndex = (readFrameIndex + firstChunk) % capacityFrames
                availableFrames -= firstChunk
            }

            // Copy second chunk.
            if secondChunk > 0 {
                let srcBase = readFrameIndex * channels
                storage.withUnsafeBufferPointer { src in
                    dst.advanced(by: firstChunk * channels).update(from: src.baseAddress!.advanced(by: srcBase), count: secondChunk * channels)
                }
                readFrameIndex = (readFrameIndex + secondChunk) % capacityFrames
                availableFrames -= secondChunk
            }

            condition.signal()
            return framesToRead == frameCount
        }
    }

    private let ring: RingBuffer
    private let decodeQueue: DispatchQueue
    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    private var didStart: Bool = false
    private var cancelled: Bool = false

    private init(ring: RingBuffer, decodeQueue: DispatchQueue) {
        self.ring = ring
        self.decodeQueue = decodeQueue
    }

    static func make(
        url: URL,
        targetSampleRate: Double,
        targetChannels: Int,
        startSeconds: Double,
        durationSeconds: Double,
        maxFramesPerRenderCall: Int,
        bufferSeconds: Double = 2.0
    ) async throws -> FileClipStream {
        let channels = max(1, targetChannels)
        let minCapacityFrames = max(1, maxFramesPerRenderCall * 4)
        let desiredCapacityFrames = Int((targetSampleRate * max(0.25, bufferSeconds)).rounded(.toNearestOrAwayFromZero))
        let capacityFrames = max(minCapacityFrames, desiredCapacityFrames)

        let ring = RingBuffer(capacityFrames: capacityFrames, channels: channels)
        let stream = FileClipStream(ring: ring, decodeQueue: DispatchQueue(label: "metavis.audio.filestream.decode", qos: .userInitiated))

        let configuredFrames = Int((max(0.0, durationSeconds) * targetSampleRate).rounded(.toNearestOrAwayFromZero))
        FileAudioStreamingDiagnostics.recordConfigured(durationFrames: configuredFrames)

        try await stream.configure(url: url, targetSampleRate: targetSampleRate, targetChannels: channels, startSeconds: startSeconds, durationSeconds: durationSeconds)
        stream.startDecoding()
        return stream
    }

    func cancel() {
        cancelled = true
        ring.cancel()
        decodeQueue.async { [weak self] in
            self?.reader?.cancelReading()
            self?.reader = nil
            self?.output = nil
        }
    }

    func readInterleavedFramesBlocking(frameCount: Int, into dst: UnsafeMutablePointer<Float>, channels: Int) -> Bool {
        _ = channels // kept for call-site clarity; ring is configured to match.
        return ring.readInterleavedBlocking(into: dst, frameCount: frameCount)
    }

    private func configure(
        url: URL,
        targetSampleRate: Double,
        targetChannels: Int,
        startSeconds: Double,
        durationSeconds: Double
    ) async throws {
        let asset = AVURLAsset(url: url)

        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else {
            // No audio track: treat as finished.
            ring.markFinished()
            return
        }

        let r = try AVAssetReader(asset: asset)
        let channels = max(1, targetChannels)

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: targetSampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let out = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        out.alwaysCopiesSampleData = false
        guard r.canAdd(out) else {
            throw NSError(domain: "MetaVisAudio", code: 210, userInfo: [NSLocalizedDescriptionKey: "Cannot add AVAssetReaderTrackOutput for audio track"])
        }
        r.add(out)

        // Clamp to non-negative.
        let start = max(0.0, startSeconds)
        let dur = max(0.0, durationSeconds)
        if dur > 0 {
            r.timeRange = CMTimeRange(
                start: CMTime(seconds: start, preferredTimescale: 600),
                duration: CMTime(seconds: dur, preferredTimescale: 600)
            )
        }

        guard r.startReading() else {
            throw r.error ?? NSError(domain: "MetaVisAudio", code: 211, userInfo: [NSLocalizedDescriptionKey: "AVAssetReader.startReading() failed"])
        }

        reader = r
        output = out
    }

    private func startDecoding() {
        guard !didStart else { return }
        didStart = true

        decodeQueue.async { [weak self] in
            guard let self else { return }
            guard !self.cancelled else { return }
            guard let reader = self.reader, let output = self.output else {
                self.ring.markFinished()
                return
            }

            var scratchBytes: [UInt8] = []
            scratchBytes.reserveCapacity(256 * 1024)

            while !self.cancelled && reader.status == .reading {
                guard let sampleBuffer = output.copyNextSampleBuffer() else {
                    break
                }
                guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                    continue
                }

                let totalLength = CMBlockBufferGetDataLength(blockBuffer)
                guard totalLength > 0 else { continue }

                var lengthAtOffset: Int = 0
                var totalLengthOut: Int = 0
                var dataPointer: UnsafeMutablePointer<Int8>?
                let status = CMBlockBufferGetDataPointer(
                    blockBuffer,
                    atOffset: 0,
                    lengthAtOffsetOut: &lengthAtOffset,
                    totalLengthOut: &totalLengthOut,
                    dataPointerOut: &dataPointer
                )

                if status == kCMBlockBufferNoErr, let dataPointer, totalLengthOut == totalLength {
                    let floatCount = totalLength / MemoryLayout<Float>.size
                    let typed = dataPointer.withMemoryRebound(to: Float.self, capacity: floatCount) { ptr in
                        UnsafeBufferPointer(start: ptr, count: floatCount)
                    }
                    let framesDecoded = floatCount / max(1, self.ring.channels)
                    FileAudioStreamingDiagnostics.addDecoded(frames: framesDecoded)
                    self.ring.writeInterleaved(typed, frameCount: framesDecoded)
                } else {
                    // Fallback copy for non-contiguous cases (reuse scratch).
                    if scratchBytes.count < totalLength {
                        scratchBytes = [UInt8](repeating: 0, count: totalLength)
                    }
                    let copyStatus = CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: totalLength, destination: &scratchBytes)
                    if copyStatus == kCMBlockBufferNoErr {
                        scratchBytes.withUnsafeBytes { raw in
                            let floatCount = raw.count / MemoryLayout<Float>.size
                            let floats = raw.bindMemory(to: Float.self)
                            let framesDecoded = floatCount / max(1, self.ring.channels)
                            FileAudioStreamingDiagnostics.addDecoded(frames: framesDecoded)
                            self.ring.writeInterleaved(floats, frameCount: framesDecoded)
                        }
                    }
                }
            }

            if reader.status == .failed {
                // Treat failure as end-of-stream; caller will output silence.
                _ = reader.error
            }

            self.ring.markFinished()
        }
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
