import Foundation
import AVFoundation
import CoreVideo
import CoreMedia
import Vision
import Accelerate
import CryptoKit
import MetaVisCore

public struct MasterSensorIngestor: Sendable {

    public struct Options: Sendable {
        /// Optional start offset into the video for analysis (seconds).
        /// Default 0 analyzes from the beginning.
        public var videoStartSeconds: Double
        public var videoStrideSeconds: Double
        public var maxVideoSeconds: Double
        public var audioAnalyzeSeconds: Double

        /// Optional keyframe stride for segmentation (seconds).
        /// When set, segmentation is computed on keyframes and propagated between keyframes using optical flow.
        /// When nil, segmentation is computed on every sampled frame.
        public var segmentationKeyframeStrideSeconds: Double?

        public var enableFaces: Bool
        public var enableSegmentation: Bool
        public var enableAudio: Bool
        public var enableWarnings: Bool
        public var enableDescriptors: Bool
        public var enableSuggestedStart: Bool

        public init(
            videoStartSeconds: Double = 0.0,
            videoStrideSeconds: Double = 1.0,
            maxVideoSeconds: Double = 10.0,
            audioAnalyzeSeconds: Double = 10.0,
            segmentationKeyframeStrideSeconds: Double? = nil,
            enableFaces: Bool = true,
            enableSegmentation: Bool = true,
            enableAudio: Bool = true,
            enableWarnings: Bool = true,
            enableDescriptors: Bool = true,
            enableSuggestedStart: Bool = true
        ) {
            self.videoStartSeconds = videoStartSeconds
            self.videoStrideSeconds = videoStrideSeconds
            self.maxVideoSeconds = maxVideoSeconds
            self.audioAnalyzeSeconds = audioAnalyzeSeconds

            self.segmentationKeyframeStrideSeconds = segmentationKeyframeStrideSeconds

            self.enableFaces = enableFaces
            self.enableSegmentation = enableSegmentation
            self.enableAudio = enableAudio
            self.enableWarnings = enableWarnings
            self.enableDescriptors = enableDescriptors
            self.enableSuggestedStart = enableSuggestedStart
        }
    }

    private let options: Options

    public init(videoStrideSeconds: Double = 1.0, maxVideoSeconds: Double = 10.0, audioAnalyzeSeconds: Double = 10.0) {
        self.options = Options(videoStrideSeconds: videoStrideSeconds, maxVideoSeconds: maxVideoSeconds, audioAnalyzeSeconds: audioAnalyzeSeconds)
    }

    public init(_ options: Options) {
        self.options = options
    }

    public func ingest(url: URL) async throws -> MasterSensors {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let durationSeconds = duration.seconds.isFinite ? duration.seconds : 0.0

        let startSeconds = max(0.0, min(durationSeconds, options.videoStartSeconds))
        let analyzedSeconds = min(options.maxVideoSeconds, max(0.0, durationSeconds - startSeconds))

        // Use a content hash (not a path) so stable IDs remain stable across machines and renames.
        let sourceKey = try SourceContentHashV1.shared.contentHashHex(for: url)

        let videoInfo = try await readVideoInfo(asset: asset)
        let videoOut = try await readVideoSamples(asset: asset, durationSeconds: durationSeconds, sourceKey: sourceKey)
        let videoSamples = videoOut.samples

        let scene = SceneContextHeuristics.inferScene(from: videoSamples)
        let audioAnalysis: AudioAnalysis
        if options.enableAudio {
            audioAnalysis = try await readAudioAnalysis(asset: asset, maxAnalyzeSeconds: options.audioAnalyzeSeconds)
        } else {
            audioAnalysis = AudioAnalysis(
                info: AudioInfo(approxRMSdBFS: -100.0, approxPeakDB: -100.0, dominantFrequencyHz: nil, spectralCentroidHz: nil),
                segments: [],
                frames: [],
                beats: []
            )
        }

        let warnings: [MasterSensors.WarningSegment]
        if options.enableWarnings {
            let videoWarnings = EditorWarningModel.warnings(from: videoSamples)
            let audioWarnings: [MasterSensors.WarningSegment]
            if options.enableAudio {
                audioWarnings = AudioWarningModel.warnings(
                    audio: .init(
                        approxRMSdBFS: audioAnalysis.info.approxRMSdBFS,
                        approxPeakDB: audioAnalysis.info.approxPeakDB,
                        dominantFrequencyHz: audioAnalysis.info.dominantFrequencyHz,
                        spectralCentroidHz: audioAnalysis.info.spectralCentroidHz
                    ),
                    segments: audioAnalysis.segments,
                    analyzedSeconds: analyzedSeconds
                )
            } else {
                audioWarnings = []
            }
            var combined = videoWarnings + audioWarnings + videoOut.deviceWarnings
            combined.sort {
                if $0.start != $1.start { return $0.start < $1.start }
                if $0.end != $1.end { return $0.end < $1.end }
                if $0.severity.rawValue != $1.severity.rawValue { return $0.severity.rawValue < $1.severity.rawValue }
                return $0.governedReasonCodes.map { $0.rawValue }.joined(separator: ",") < $1.governedReasonCodes.map { $0.rawValue }.joined(separator: ",")
            }
            warnings = combined
        } else {
            warnings = []
        }

        let suggestedStart: MasterSensors.SuggestedStart?
        if options.enableSuggestedStart {
            suggestedStart = AutoStartHeuristics.suggestStart(
                videoSamples: videoSamples,
                audioSegments: audioAnalysis.segments,
                analyzedSeconds: analyzedSeconds
            )
        } else {
            suggestedStart = nil
        }

        let descriptors: [MasterSensors.DescriptorSegment]
        if options.enableDescriptors {
            descriptors = DescriptorBuilder.build(
                videoSamples: videoSamples,
                audioSegments: audioAnalysis.segments,
                audioBeats: audioAnalysis.beats,
                warnings: warnings,
                suggestedStart: suggestedStart,
                scene: scene,
                analyzedSeconds: analyzedSeconds
            )
        } else {
            descriptors = []
        }

        let summary = MasterSensors.Summary(
            analyzedSeconds: analyzedSeconds,
            scene: scene,
            audio: .init(
                approxRMSdBFS: audioAnalysis.info.approxRMSdBFS,
                approxPeakDB: audioAnalysis.info.approxPeakDB,
                dominantFrequencyHz: audioAnalysis.info.dominantFrequencyHz,
                spectralCentroidHz: audioAnalysis.info.spectralCentroidHz
            )
        )

        return MasterSensors(
            source: .init(
                path: url.path,
                durationSeconds: durationSeconds,
                width: videoInfo.width,
                height: videoInfo.height,
                nominalFPS: videoInfo.nominalFPS
            ),
            sampling: .init(
                videoStrideSeconds: options.videoStrideSeconds,
                maxVideoSeconds: analyzedSeconds,
                audioAnalyzeSeconds: options.audioAnalyzeSeconds
            ),
            videoSamples: videoSamples,
            audioSegments: audioAnalysis.segments,
            audioFrames: audioAnalysis.frames.isEmpty ? nil : audioAnalysis.frames,
            audioBeats: audioAnalysis.beats.isEmpty ? nil : audioAnalysis.beats,
            warnings: warnings,
            descriptors: descriptors.isEmpty ? nil : descriptors,
            suggestedStart: suggestedStart,
            summary: summary
        )
    }

    // MARK: - Video

    private struct VideoInfo: Sendable {
        var width: Int?
        var height: Int?
        var nominalFPS: Double?
    }

    private func readVideoInfo(asset: AVAsset) async throws -> VideoInfo {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { return VideoInfo() }

        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let transformed = size.applying(transform)
        let w = Int(abs(transformed.width).rounded())
        let h = Int(abs(transformed.height).rounded())

        let fps = Double(try await track.load(.nominalFrameRate))

        return VideoInfo(
            width: (w > 0) ? w : nil,
            height: (h > 0) ? h : nil,
            nominalFPS: (fps.isFinite && fps > 0) ? fps : nil
        )
    }

    private func readVideoSamples(asset: AVAsset, durationSeconds: Double) async throws -> [MasterSensors.VideoSample] {
        return try await readVideoSamples(asset: asset, durationSeconds: durationSeconds, sourceKey: "").samples
    }

    private struct VideoSamplingOutput: Sendable {
        var samples: [MasterSensors.VideoSample]
        var deviceWarnings: [MasterSensors.WarningSegment]
    }

    private func readVideoSamples(asset: AVAsset, durationSeconds: Double, sourceKey: String) async throws -> VideoSamplingOutput {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { return VideoSamplingOutput(samples: [], deviceWarnings: []) }

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return VideoSamplingOutput(samples: [], deviceWarnings: []) }
        reader.add(output)

        let startSeconds = max(0.0, min(durationSeconds, options.videoStartSeconds))
        let analyzeSeconds = min(options.maxVideoSeconds, max(0.0, durationSeconds - startSeconds))
        if analyzeSeconds <= 0.0001 { return VideoSamplingOutput(samples: [], deviceWarnings: []) }

        let stride = max(0.25, options.videoStrideSeconds)
        let requestedTimes: [Double] = strideTimes(maxSeconds: analyzeSeconds, stride: stride)

        guard reader.startReading() else { return VideoSamplingOutput(samples: [], deviceWarnings: []) }

        let tracksDevice = TracksDevice()
        let maskDevice: MaskDevice = {
            if let stride = options.segmentationKeyframeStrideSeconds, stride.isFinite, stride > 0.0001 {
                return MaskDevice(options: .init(mode: .keyframes(strideSeconds: stride)))
            }
            return MaskDevice()
        }()
        let videoAnalyzer = VideoAnalyzer()

        var deviceLifecycles: [AnyPerceptionDeviceLifecycle] = []
        deviceLifecycles.reserveCapacity(2)
        if options.enableFaces {
            deviceLifecycles.append(.init(tracksDevice, name: "TracksDevice"))
        }
        if options.enableSegmentation {
            deviceLifecycles.append(.init(maskDevice, name: "MaskDevice"))
        }

        var samples: [MasterSensors.VideoSample] = []
        samples.reserveCapacity(requestedTimes.count)

        struct Mark {
            var t: Double
            var sev: MasterSensors.TrafficLight
            var reasons: [ReasonCodeV1]
        }

        var deviceMarks: [Mark] = []
        deviceMarks.reserveCapacity(requestedTimes.count)

        // Deterministic mapping: Vision UUIDs are not guaranteed stable across runs.
        // We assign stable per-run indices based on sorted rect order at first sight,
        // then derive deterministic UUIDs from (sourceKey, index).
        var stableIndexByVisionID: [UUID: Int] = [:]
        var nextStableIndex: Int = 0

        var timeIndex = 0
        var nextTime = requestedTimes[timeIndex]

        return try await PerceptionDeviceGroupV1.withWarmedUp(deviceLifecycles) {
            while reader.status == .reading, let sb = output.copyNextSampleBuffer() {
                let pts = CMSampleBufferGetPresentationTimeStamp(sb)
                let t = pts.isValid ? pts.seconds : 0.0
                if t + 0.0001 < (startSeconds + nextTime) {
                    continue
                }

                guard let pb = CMSampleBufferGetImageBuffer(sb) else { continue }

                let trackRes: TracksDevice.TrackResult?
                if options.enableFaces {
                    trackRes = try await tracksDevice.infer(.init(pixelBuffer: pb))
                } else {
                    trackRes = nil
                }

                let maskRes: MaskDevice.MaskResult?
                if options.enableSegmentation {
                    let sampleT = max(0.0, min(analyzeSeconds, t - startSeconds))
                    maskRes = try await maskDevice.infer(.init(pixelBuffer: pb, kind: .foreground, timeSeconds: sampleT))
                } else {
                    maskRes = nil
                }

                let faces: [MasterSensors.Face]
                if options.enableFaces {
                    // Track faces (stable UUID per tracker).
                    let tracked = trackRes?.tracks ?? [:]
                    var items = tracked.map { (visionID: $0.key, rect: Self.quantizeNormalizedRect($0.value)) }
                    // Sort by geometry (deterministic) rather than Vision UUID string.
                    items.sort {
                        if $0.rect.minX != $1.rect.minX { return $0.rect.minX < $1.rect.minX }
                        if $0.rect.minY != $1.rect.minY { return $0.rect.minY < $1.rect.minY }
                        let a0 = $0.rect.width * $0.rect.height
                        let a1 = $1.rect.width * $1.rect.height
                        if a0 != a1 { return a0 > a1 }
                        return $0.visionID.uuidString < $1.visionID.uuidString
                    }

                    faces = items.map { item in
                        let idx: Int
                        if let existing = stableIndexByVisionID[item.visionID] {
                            idx = existing
                        } else {
                            idx = nextStableIndex
                            stableIndexByVisionID[item.visionID] = idx
                            nextStableIndex += 1
                        }
                        let stableID = deterministicUUID(sourceKey: sourceKey, index: idx)
                        // MVP identity: stable personId derived from stable index.
                        // This intentionally does not claim cross-shot re-identification yet.
                        return MasterSensors.Face(trackId: stableID, rect: item.rect, personId: "P\(idx)")
                    }
                } else {
                    faces = []
                }

                let maskPresence: Double?
                if options.enableSegmentation {
                    maskPresence = maskRes?.metrics.coverage
                } else {
                    maskPresence = nil
                }

                // Device-level stability warnings (explicit uncertainty; never silent degrade).
                // Keep narrow to avoid noisy warnings on clean footage.
                let sampleT = max(0.0, min(analyzeSeconds, t - startSeconds))
                if let mr = maskRes, mr.evidenceConfidence.reasons.contains(.mask_unstable_iou) {
                    deviceMarks.append(Mark(t: sampleT, sev: .yellow, reasons: [.mask_unstable_iou]))
                }
                if let tr = trackRes, tr.metrics.reacquired {
                    deviceMarks.append(Mark(t: sampleT, sev: .yellow, reasons: [.track_reacquired]))
                }

                let peopleEstimate: Int?
                if options.enableFaces || options.enableSegmentation {
                    let faceCount = faces.count
                    if let maskPresence, maskPresence > 0.01 {
                        peopleEstimate = max(faceCount, 1)
                    } else {
                        peopleEstimate = faceCount
                    }
                } else {
                    peopleEstimate = nil
                }

                let analysis = try videoAnalyzer.analyze(pixelBuffer: pb)
                let meanLuma = meanFromHistogram(analysis.lumaHistogram)

                let dom = analysis.dominantColors.map { SIMD3<Double>(Double($0.x), Double($0.y), Double($0.z)) }

                let s = MasterSensors.VideoSample(
                    time: sampleT,
                    meanLuma: meanLuma,
                    skinLikelihood: Double(analysis.skinToneLikelihood),
                    dominantColors: dom,
                    faces: faces,
                    personMaskPresence: maskPresence,
                    peopleCountEstimate: peopleEstimate
                )
                samples.append(s)

                timeIndex += 1
                if timeIndex >= requestedTimes.count { break }
                nextTime = requestedTimes[timeIndex]
            }

            let deviceWarnings: [MasterSensors.WarningSegment] = {
                guard !deviceMarks.isEmpty else { return [] }
                let sorted = deviceMarks.sorted { $0.t < $1.t }

                var segments: [MasterSensors.WarningSegment] = []
                segments.reserveCapacity(sorted.count)

                var current = sorted[0]
                var start = current.t

                func flush(end: Double) {
                    let mergedReasons = Array(Set(current.reasons)).sorted()
                    if mergedReasons.isEmpty && current.sev == .green { return }
                    segments.append(
                        MasterSensors.WarningSegment(
                            start: start,
                            end: max(start + 0.001, min(analyzeSeconds, end)),
                            severity: current.sev,
                            reasonCodes: mergedReasons
                        )
                    )
                }

                for i in 1..<sorted.count {
                    let m = sorted[i]
                    if m.sev == current.sev {
                        current.reasons.append(contentsOf: m.reasons)
                        continue
                    }
                    flush(end: m.t)
                    current = m
                    start = m.t
                }

                flush(end: (sorted.last?.t ?? 0.0) + 0.001)
                return segments
            }()

            // If we undershot (e.g. reader ended early), return what we have.
            return VideoSamplingOutput(samples: samples, deviceWarnings: deviceWarnings)
        }
    }

    private func deterministicUUID(sourceKey: String, index: Int) -> UUID {
        // UUID derived from SHA256(sourceKey|"master_track"|index)
        let input = "\(sourceKey)|master_track|\(index)"
        let digest = SHA256.hash(data: Data(input.utf8))
        var bytes = Array(digest)
        // Use first 16 bytes and set RFC4122 variant + version 5-like bits.
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // version 5
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // variant

        let u = (
            UInt8(bytes[0]), UInt8(bytes[1]), UInt8(bytes[2]), UInt8(bytes[3]),
            UInt8(bytes[4]), UInt8(bytes[5]), UInt8(bytes[6]), UInt8(bytes[7]),
            UInt8(bytes[8]), UInt8(bytes[9]), UInt8(bytes[10]), UInt8(bytes[11]),
            UInt8(bytes[12]), UInt8(bytes[13]), UInt8(bytes[14]), UInt8(bytes[15])
        )
        return UUID(uuid: u)
    }

    private static func quantizeNormalizedRect(_ rect: CGRect) -> CGRect {
        // Quantize to a fixed grid to avoid tiny Vision float jitter breaking determinism.
        // 1e-4 gives sub-pixel stability for typical outputs while remaining precise enough for masks.
        let step: CGFloat = 0.0001

        func q(_ v: CGFloat) -> CGFloat {
            guard v.isFinite else { return 0 }
            return (v / step).rounded() * step
        }

        var x = q(rect.origin.x)
        var y = q(rect.origin.y)
        var w = q(rect.size.width)
        var h = q(rect.size.height)

        x = max(0, min(1, x))
        y = max(0, min(1, y))
        w = max(0, min(1 - x, w))
        h = max(0, min(1 - y, h))

        return CGRect(x: x, y: y, width: w, height: h)
    }

    private static func maskPresenceRatio(pixelBuffer: CVPixelBuffer) -> Double {
        let fmt = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard fmt == kCVPixelFormatType_OneComponent8 else { return 0.0 }

        guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else { return 0.0 }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 0.0 }
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        let bpr = CVPixelBufferGetBytesPerRow(pixelBuffer)

        var countOn: Int64 = 0
        let countAll: Int64 = Int64(max(1, w * h))

        for y in 0..<h {
            let row = base.advanced(by: y * bpr).assumingMemoryBound(to: UInt8.self)
            for x in 0..<w {
                if row[x] > 16 { // low threshold; mask is 0..255
                    countOn += 1
                }
            }
        }

        return Double(countOn) / Double(countAll)
    }

    private func strideTimes(maxSeconds: Double, stride: Double) -> [Double] {
        var t: Double = 0.0
        var out: [Double] = []
        while t < maxSeconds - 0.0001 {
            out.append(t)
            t += stride
        }
        if out.isEmpty { out = [0.0] }
        return out
    }

    private func meanFromHistogram(_ hist: [Float]) -> Double {
        guard !hist.isEmpty else { return 0.0 }
        var sum: Double = 0.0
        for i in 0..<hist.count {
            sum += Double(i) * Double(hist[i])
        }
        let maxIndex = Double(hist.count - 1)
        return maxIndex > 0 ? (sum / maxIndex) : 0.0
    }

    // MARK: - Audio (approx)

    private struct AudioInfo: Sendable {
        var approxRMSdBFS: Float
        var approxPeakDB: Float
        var dominantFrequencyHz: Double?
        var spectralCentroidHz: Double?
    }

    private struct AudioAnalysis: Sendable {
        var info: AudioInfo
        var segments: [MasterSensors.AudioSegment]
        var frames: [MasterSensors.AudioFrame]
        var beats: [MasterSensors.AudioBeat]
    }

    private func readAudioAnalysis(asset: AVAsset, maxAnalyzeSeconds: Double) async throws -> AudioAnalysis {
        guard maxAnalyzeSeconds > 0.0001 else {
            return AudioAnalysis(
                info: AudioInfo(approxRMSdBFS: -100.0, approxPeakDB: -100.0, dominantFrequencyHz: nil, spectralCentroidHz: nil),
                segments: [],
                frames: [],
                beats: []
            )
        }

        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else {
            return AudioAnalysis(
                info: AudioInfo(approxRMSdBFS: -100.0, approxPeakDB: -100.0, dominantFrequencyHz: nil, spectralCentroidHz: nil),
                segments: [],
                frames: [],
                beats: []
            )
        }

        let reader = try AVAssetReader(asset: asset)
        let stopTime = CMTime(seconds: maxAnalyzeSeconds, preferredTimescale: 600)
        reader.timeRange = CMTimeRange(start: .zero, duration: stopTime)

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            return AudioAnalysis(
                info: AudioInfo(approxRMSdBFS: -100.0, approxPeakDB: -100.0, dominantFrequencyHz: nil, spectralCentroidHz: nil),
                segments: [],
                frames: [],
                beats: []
            )
        }
        reader.add(output)

        guard reader.startReading() else {
            return AudioAnalysis(
                info: AudioInfo(approxRMSdBFS: -100.0, approxPeakDB: -100.0, dominantFrequencyHz: nil, spectralCentroidHz: nil),
                segments: [],
                frames: [],
                beats: []
            )
        }

        var peak: Float = 0
        var sumSquares: Double = 0
        var sampleCount: Int64 = 0

        var sampleRate: Double = 0
        var channels: Int = 1
        var monoSamples: [Float] = []
        monoSamples.reserveCapacity(Int(48_000.0 * min(maxAnalyzeSeconds, 10.0)))

        while reader.status == .reading {
            guard let sb = output.copyNextSampleBuffer() else { break }

            if sampleRate <= 0 {
                if let desc = CMSampleBufferGetFormatDescription(sb),
                   let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(desc) {
                    let asbd = asbdPtr.pointee
                    sampleRate = asbd.mSampleRate
                    channels = max(1, Int(asbd.mChannelsPerFrame))
                }
            }

            func consumeFloats(_ floats: UnsafeBufferPointer<Float>) {
                // Stats across all channels.
                for v in floats {
                    if v.isFinite {
                        let a = abs(v)
                        if a > peak { peak = a }
                        sumSquares += Double(v) * Double(v)
                        sampleCount += 1
                    }
                }

                // Build mono for VAD.
                guard !floats.isEmpty else { return }
                if channels <= 1 {
                    monoSamples.append(contentsOf: floats)
                    return
                }

                let frameCount = floats.count / channels
                if frameCount <= 0 { return }
                monoSamples.reserveCapacity(monoSamples.count + frameCount)
                for frame in 0..<frameCount {
                    var sum: Float = 0
                    let base = frame * channels
                    for c in 0..<channels {
                        sum += floats[base + c]
                    }
                    monoSamples.append(sum / Float(channels))
                }
            }

            // Fast path: contiguous CMBlockBuffer.
            if let block = CMSampleBufferGetDataBuffer(sb) {
                var length: Int = 0
                var dataPointer: UnsafeMutablePointer<Int8>?
                let status = CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
                if status == kCMBlockBufferNoErr, let dataPointer, length > 0 {
                    let floatCount = length / MemoryLayout<Float>.stride
                    let base = UnsafeRawPointer(dataPointer).bindMemory(to: Float.self, capacity: floatCount)
                    consumeFloats(UnsafeBufferPointer(start: base, count: floatCount))
                    continue
                }
            }

            // Fallback: AudioBufferList extraction.
            let channelsHint = 2
            let size = MemoryLayout<AudioBufferList>.size + (channelsHint - 1) * MemoryLayout<AudioBuffer>.size
            let ablRaw = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<AudioBufferList>.alignment)
            defer { ablRaw.deallocate() }
            let ablPtr = ablRaw.bindMemory(to: AudioBufferList.self, capacity: 1)
            ablPtr.pointee.mNumberBuffers = UInt32(channelsHint)

            var blockBuffer: CMBlockBuffer?
            let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
                sb,
                bufferListSizeNeededOut: nil,
                bufferListOut: ablPtr,
                bufferListSize: size,
                blockBufferAllocator: kCFAllocatorDefault,
                blockBufferMemoryAllocator: kCFAllocatorDefault,
                flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
                blockBufferOut: &blockBuffer
            )
            guard status == noErr else { continue }
            let buffers = UnsafeMutableAudioBufferListPointer(ablPtr)
            for b in buffers {
                guard let data = b.mData, b.mDataByteSize > 0 else { continue }
                let count = Int(b.mDataByteSize) / MemoryLayout<Float>.stride
                let base = data.assumingMemoryBound(to: Float.self)
                consumeFloats(UnsafeBufferPointer(start: base, count: count))
            }
        }

        if sampleCount <= 0 {
            return AudioAnalysis(
                info: AudioInfo(approxRMSdBFS: -100.0, approxPeakDB: -100.0, dominantFrequencyHz: nil, spectralCentroidHz: nil),
                segments: [],
                frames: [],
                beats: []
            )
        }

        let meanSquare = sumSquares / Double(sampleCount)
        let rms = Float(sqrt(max(0, meanSquare)))

        func db(_ x: Float) -> Float { x > 0 ? (20.0 * log10(x)) : -100.0 }

        func quantize(_ x: Float, step: Float) -> Float {
            guard x.isFinite, step.isFinite, step > 0 else { return x }
            return (x / step).rounded() * step
        }

        func quantize(_ x: Double, step: Double) -> Double {
            guard x.isFinite, step.isFinite, step > 0 else { return x }
            return (x / step).rounded() * step
        }

        let fft: (dominantHz: Double, centroidHz: Double)?
        if sampleRate > 1000, monoSamples.count >= 1024 {
            fft = Self.audioFFTDominantAndCentroidHz(monoSamples: monoSamples, sampleRate: sampleRate)
        } else {
            fft = nil
        }

        // Quantize to guarantee determinism across runs (AVAssetReader chunking + float math
        // can introduce tiny drift at ~1e-6 that breaks exact Equatable/byte-stable JSON tests).
        let info = AudioInfo(
            approxRMSdBFS: quantize(db(rms), step: 0.0001),
            approxPeakDB: quantize(db(peak), step: 0.0001),
            dominantFrequencyHz: fft.map { quantize($0.dominantHz, step: 0.01) },
            spectralCentroidHz: fft.map { quantize($0.centroidHz, step: 0.01) }
        )

        let segments: [MasterSensors.AudioSegment]
        let frames: [MasterSensors.AudioFrame]
        let beats: [MasterSensors.AudioBeat]
        if sampleRate > 1000, !monoSamples.isEmpty {
            segments = AudioVADHeuristics.segment(
                mono: monoSamples,
                sampleRate: sampleRate,
                windowSeconds: 0.5,
                hopSeconds: 0.25
            )
            frames = AudioVADHeuristics.frames(
                mono: monoSamples,
                sampleRate: sampleRate,
                windowSeconds: 0.5,
                hopSeconds: 0.25
            )
            beats = AudioVADHeuristics.beats(from: frames)
        } else {
            segments = []
            frames = []
            beats = []
        }

        return AudioAnalysis(info: info, segments: segments, frames: frames, beats: beats)
    }

    private static func audioFFTDominantAndCentroidHz(monoSamples: [Float], sampleRate: Double) -> (dominantHz: Double, centroidHz: Double)? {
        // Deterministic: fixed FFT size, fixed window location (start of analyzed range).
        let fftN = 1024
        guard monoSamples.count >= fftN, sampleRate.isFinite, sampleRate > 1000 else { return nil }

        // Pick a deterministic window that is not silence.
        // Scan forward in fixed hops and pick the first window with RMS above a small threshold.
        let hop = 512
        let maxScanSamples = min(monoSamples.count - fftN, Int(sampleRate * 2.0)) // scan first ~2s
        var chosenOffset = 0
        monoSamples.withUnsafeBufferPointer { s in
            var offset = 0
            while offset <= maxScanSamples {
                var meanSquare: Float = 0
                vDSP_measqv(s.baseAddress!.advanced(by: offset), 1, &meanSquare, vDSP_Length(fftN))
                let rms = sqrt(max(0, meanSquare))
                if rms > 0.005 {
                    chosenOffset = offset
                    break
                }
                offset += hop
            }
        }

        guard let dftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(fftN), vDSP_DFT_Direction.FORWARD) else { return nil }
        defer { vDSP_DFT_DestroySetup(dftSetup) }

        var real = [Float](repeating: 0, count: fftN)
        var imag = [Float](repeating: 0, count: fftN)
        var outReal = [Float](repeating: 0, count: fftN)
        var outImag = [Float](repeating: 0, count: fftN)
        var mags = [Float](repeating: 0, count: fftN / 2)

        // Copy chosen window (deterministic), then remove DC offset to avoid 0 Hz dominating.
        real.withUnsafeMutableBufferPointer { r in
            monoSamples.withUnsafeBufferPointer { s in
                r.baseAddress!.update(from: s.baseAddress!.advanced(by: chosenOffset), count: fftN)
            }
        }
        var mean: Float = 0
        vDSP_meanv(real, 1, &mean, vDSP_Length(fftN))
        var negMean = -mean
        vDSP_vsadd(real, 1, &negMean, &real, 1, vDSP_Length(fftN))

        vDSP_DFT_Execute(dftSetup, &real, &imag, &outReal, &outImag)

        let bins = fftN / 2
        outReal.withUnsafeMutableBufferPointer { rPtr in
            outImag.withUnsafeMutableBufferPointer { iPtr in
                var split = DSPSplitComplex(realp: rPtr.baseAddress!, imagp: iPtr.baseAddress!)
                vDSP_zvabs(&split, 1, &mags, 1, vDSP_Length(bins))
            }
        }

        // Ignore DC / near-DC bins (often dominated by residual offset and windowing).
        if bins > 0 { mags[0] = 0 }
        if bins > 1 { mags[1] = 0 }

        var maxVal: Float = 0
        var maxIndex: vDSP_Length = 0
        vDSP_maxvi(&mags, 1, &maxVal, &maxIndex, vDSP_Length(bins))
        let binHz = (sampleRate / 2.0) / Double(bins)
        let dominantHz = Double(maxIndex) * binHz

        var sumMag: Double = 0
        var sumWeighted: Double = 0
        for i in 2..<bins {
            let m = Double(mags[i])
            sumMag += m
            sumWeighted += m * (Double(i) * binHz)
        }
        let centroidHz = (sumMag > 1e-12) ? (sumWeighted / sumMag) : 0.0
        return (dominantHz: dominantHz, centroidHz: centroidHz)
    }
}
