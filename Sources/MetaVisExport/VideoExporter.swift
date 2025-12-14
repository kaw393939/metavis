import Foundation
import AVFoundation
import CoreVideo
import VideoToolbox
import MetaVisCore
import MetaVisTimeline
import MetaVisAudio
import MetaVisSimulation

/// Handles the export of a Timeline to a video file.
public actor VideoExporter: VideoExporting {
    
    private let device: any RenderDevice
    private let trace: any TraceSink
    
    public init(engine: MetalSimulationEngine, trace: any TraceSink = NoOpTraceSink()) {
        self.device = MetalRenderDevice(engine: engine)
        self.trace = trace
    }

    public init(device: any RenderDevice, trace: any TraceSink = NoOpTraceSink()) {
        self.device = device
        self.trace = trace
    }
    
    private nonisolated func logDebug(_ msg: String) {
        let str = "\(Date()): \(msg)\n"
        if let data = str.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: "/tmp/metavis_debug.log")) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? str.write(to: URL(fileURLWithPath: "/tmp/metavis_debug.log"), atomically: true, encoding: .utf8)
            }
        }
    }
    
    /// Exports the timeline to the specified URL.
    /// - Parameters:
    ///   - timeline: The timeline to export.
    ///   - outputURL: The file URL to write to (must be .mov or .mp4).
    ///   - quality: The quality profile (determines resolution/bitdepth).
    ///   - frameRate: The target frame rate (default 24).
    ///   - codec: The video codec (HEVC or ProRes).
    public func export(
        timeline: Timeline,
        to outputURL: URL,
        quality: QualityProfile,
        frameRate: Int32 = 24,
        codec: AVVideoCodecType = .hevc,
        audioPolicy: AudioPolicy = .auto,
        governance: ExportGovernance = .none
    ) async throws {

        do {

        guard frameRate > 0 else {
            throw NSError(domain: "MetaVisExport", code: 99, userInfo: [NSLocalizedDescriptionKey: "Invalid frameRate: \(frameRate)"])
        }

            try Self.validateExport(quality: quality, governance: governance)

            // Strict feature registry preflight: unknown IDs fail fast.
            try await ExportPreflight.validateTimelineFeatureIDs(timeline, trace: trace)

            await trace.record(
                "export.begin",
                fields: [
                    "output": outputURL.lastPathComponent,
                    "quality": quality.name,
                    "fps": String(frameRate),
                    "codec": codec.rawValue
                ]
            )
        
            logDebug("🎬 [VideoExporter] Export request received for \(outputURL.lastPathComponent)")
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: outputURL.path) {
                try fileManager.removeItem(at: outputURL)
            }
        
        // 1. Setup Asset Writer
            let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        
        // 10-bit Support
        // Use 64-bit RGBA Half (Float16) format to match legacy MetaVis implementation
        // This provides sufficient precision for scene-linear values
            let is10Bit = quality.colorDepth >= 10
            let pixelFormat = kCVPixelFormatType_64RGBAHalf  // 16-bit float RGBA
        
        // Compression Settings
              var compressionProperties: [String: Any] = [:]
              if is10Bit && codec == .hevc {
                  // Note: Using 16-bit float input with 10-bit HEVC codec
                  compressionProperties[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main10_AutoLevel
              }

                        // Ensure a sane bitrate floor so very short exports aren't tiny.
                        let width = quality.resolutionHeight * 16 / 9
                        let height = quality.resolutionHeight
                        let fps = max(1, Int(frameRate))
                        let estimatedBitrate = Int(Double(width * height * fps) * 0.08) // ~0.08 bpp for HEVC
                        let targetBitrate = max(8_000_000, estimatedBitrate)

                        // AVFoundation keys
                        compressionProperties[AVVideoAverageBitRateKey] = targetBitrate
                        compressionProperties[AVVideoExpectedSourceFrameRateKey] = fps
                        compressionProperties[AVVideoMaxKeyFrameIntervalKey] = fps

                        // VideoToolbox keys (some encoders honor these more reliably)
                        compressionProperties[kVTCompressionPropertyKey_AverageBitRate as String] = targetBitrate
                        compressionProperties[kVTCompressionPropertyKey_ExpectedFrameRate as String] = fps
                        compressionProperties[kVTCompressionPropertyKey_MaxKeyFrameInterval as String] = fps
                        compressionProperties[kVTCompressionPropertyKey_DataRateLimits as String] = [targetBitrate / 8, 1]
        
            let outputSettings: [String: Any] = [
                AVVideoCodecKey: codec,
                AVVideoWidthKey: quality.resolutionHeight * 16 / 9, // Assuming 16:9 aspect
                AVVideoHeightKey: quality.resolutionHeight,
                AVVideoCompressionPropertiesKey: compressionProperties
            ]
        
        // Video Input
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
            input.expectsMediaDataInRealTime = false
        
        // Adaptor for Pixel Buffers
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
                    kCVPixelBufferWidthKey as String: quality.resolutionHeight * 16 / 9,
                    kCVPixelBufferHeightKey as String: quality.resolutionHeight
                ]
            )
        
            if writer.canAdd(input) {
                writer.add(input)
            } else {
                logDebug("❌ Cannot add video input")
                throw NSError(domain: "MetaVisExport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot add video input"])
            }
        
        // Audio Input
        let timelineHasAudio = timeline.tracks.contains(where: { $0.kind == .audio })
        let includeAudio: Bool
        switch audioPolicy {
        case .auto:
            includeAudio = timelineHasAudio
        case .required:
            includeAudio = true
        case .forbidden:
            includeAudio = false
        }
        let audioInput: AVAssetWriterInput?
        if includeAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 48000,
                AVEncoderBitRateKey: 128000
            ]

            let ai = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            ai.expectsMediaDataInRealTime = false

            if writer.canAdd(ai) {
                writer.add(ai)
                audioInput = ai
            } else {
                logDebug("⚠️ Warning: Cannot add audio input.")
                audioInput = nil
            }
        } else {
            audioInput = nil
        }
        
            logDebug("Writer starting...")
            guard writer.startWriting() else {
                throw writer.error ?? NSError(domain: "MetaVisExport", code: 6, userInfo: [NSLocalizedDescriptionKey: "startWriting() failed"])
            }
            writer.startSession(atSourceTime: .zero)
            logDebug("Writer started session.")
        
        // 2. Parallel Transcode
        // We Use a TaskGroup to separate Video and Audio encoding.
        // We run this in a nonisolated helper to ensure tasks don't serialize on the VideoExporter actor.
        
            let counts = try await runParallelExport(
                timeline: timeline,
                quality: quality,
                frameRate: frameRate,
                watermarkSpec: governance.watermarkSpec,
                writer: writer,
                input: input,
                audioInput: audioInput,
                adaptor: adaptor,
                device: device,
                trace: trace
            )
            
            await writer.finishWriting()
            logDebug("Writer finished.")
            logDebug("✅ Export Finished")
            
            if writer.status == .failed {
                 throw writer.error ?? NSError(domain: "MetaVisExport", code: 5, userInfo: [NSLocalizedDescriptionKey: "Writer Failed: \(writer.error?.localizedDescription ?? "Unknown")"])
            }

        // Fail fast if we wrote no frames or far fewer frames than expected.
            let expectedFrames = Int(timeline.duration.seconds * Double(frameRate))
            if counts.videoFramesAppended <= 0 {
                throw NSError(domain: "MetaVisExport", code: 7, userInfo: [NSLocalizedDescriptionKey: "No video frames appended (expected ~\(expectedFrames))"])
            }
            if expectedFrames > 0 {
                let minAcceptable = max(1, Int(Double(expectedFrames) * 0.85))
                if counts.videoFramesAppended < minAcceptable {
                    throw NSError(domain: "MetaVisExport", code: 8, userInfo: [NSLocalizedDescriptionKey: "Too few frames appended: \(counts.videoFramesAppended)/\(expectedFrames)"])
                }
            }

            await trace.record(
                "export.end",
                fields: [
                    "output": outputURL.lastPathComponent,
                    "videoFrames": String(counts.videoFramesAppended),
                    "audioChunks": String(counts.audioChunksAppended)
                ]
            )
        } catch {
            await trace.record(
                "export.error",
                fields: [
                    "output": outputURL.lastPathComponent,
                    "error": String(describing: error)
                ]
            )
            // Avoid leaving behind a tiny/partial container on failure.
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try? FileManager.default.removeItem(at: outputURL)
            }
            throw error
        }
    }

    nonisolated internal static func validateExport(quality: QualityProfile, governance: ExportGovernance) throws {
        if governance.projectLicense?.requiresWatermark == true, governance.watermarkSpec == nil {
            throw ExportGovernanceError.watermarkRequired
        }

        var maxAllowedHeight: Int?
        if let plan = governance.userPlan {
            maxAllowedHeight = plan.maxResolution
        }
        if let license = governance.projectLicense {
            maxAllowedHeight = min(maxAllowedHeight ?? license.maxExportResolution, license.maxExportResolution)
        }

        if let maxAllowedHeight, quality.resolutionHeight > maxAllowedHeight {
            throw ExportGovernanceError.resolutionNotAllowed(
                requestedHeight: quality.resolutionHeight,
                maxAllowedHeight: maxAllowedHeight
            )
        }
    }
    
    private struct ExportCounts: Sendable {
        let videoFramesAppended: Int
        let audioChunksAppended: Int
    }

    private nonisolated func runParallelExport(
        timeline: Timeline,
        quality: QualityProfile,
        frameRate: Int32,
        watermarkSpec: WatermarkSpec?,
        writer: AVAssetWriter,
        input: AVAssetWriterInput,
        audioInput: AVAssetWriterInput?,
        adaptor: AVAssetWriterInputPixelBufferAdaptor,
        device: any RenderDevice,
        trace: any TraceSink
    ) async throws -> ExportCounts {
        
        let compiler = TimelineCompiler()
        
        let expectedFrames = Int(timeline.duration.seconds * Double(frameRate))
        guard expectedFrames > 0 else {
            throw NSError(domain: "MetaVisExport", code: 9, userInfo: [NSLocalizedDescriptionKey: "Timeline duration produced 0 frames (duration=\(timeline.duration.seconds))"])
        }

        var videoCount = 0
        var audioCount = 0

        await trace.record(
            "render.video.begin",
            fields: [
                "frames": String(expectedFrames),
                "fps": String(frameRate),
                "height": String(quality.resolutionHeight)
            ]
        )

        try await withThrowingTaskGroup(of: (String, Int).self) { group in

            if let audioInput {
                // Task B: Audio (Start First)
                group.addTask {
                    let logMsg = "🔊 Audio Task Started\n"
                    if let data = logMsg.data(using: .utf8), let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: "/tmp/metavis_debug.log")) {
                        handle.seekToEndOfFile(); handle.write(data); try? handle.close()
                    }

                    let audioRenderer = AudioTimelineRenderer()
                    let sampleRate: Double = 48_000
                    let totalRange = Time.zero..<timeline.duration

                    var samplesWritten: Int64 = 0
                    try audioRenderer.renderChunks(
                        timeline: timeline,
                        timeRange: totalRange,
                        sampleRate: sampleRate,
                        maximumFrameCount: 4096
                    ) { pcmBuffer, _ in
                        // Backpressure
                        while !audioInput.isReadyForMoreMediaData {
                            Thread.sleep(forTimeInterval: 0.001)
                        }

                        if writer.status != .writing {
                            throw writer.error ?? NSError(domain: "MetaVisExport", code: 14, userInfo: [NSLocalizedDescriptionKey: "Writer not writing during audio encode: \(writer.status.rawValue)"])
                        }

                        let presentTime = CMTime(value: CMTimeValue(samplesWritten), timescale: CMTimeScale(Int32(sampleRate)))
                        if let sampleBuffer = VideoExporter.createCMSampleBufferStatic(from: pcmBuffer, presentationTime: presentTime) {
                            if audioInput.append(sampleBuffer) {
                                audioCount += 1
                            }
                        }
                        samplesWritten += Int64(pcmBuffer.frameLength)
                    }
                    audioInput.markAsFinished()
                    return ("audio", audioCount)
                }
            }
            
            // Task A: Video
            group.addTask {
                let logMsg = "📹 Video Task Started\n"
                 if let data = logMsg.data(using: .utf8), let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: "/tmp/metavis_debug.log")) {
                    handle.seekToEndOfFile(); handle.write(data); try? handle.close()
                }
                
                let totalFrames = expectedFrames
                var appended = 0
                
                for i in 0..<totalFrames {
                    if writer.status != .writing {
                        throw writer.error ?? NSError(domain: "MetaVisExport", code: 13, userInfo: [NSLocalizedDescriptionKey: "Writer not writing during video encode: \(writer.status.rawValue)"])
                    }
                    let timeSeconds = Double(i) / Double(frameRate)
                    let presentTime = CMTime(value: CMTimeValue(i), timescale: Int32(frameRate))
                    
                    // Throttle
                    while !input.isReadyForMoreMediaData {
                        try await Task.sleep(nanoseconds: 10_000_000)
                    }
                    
                    let renderTime = Time(seconds: timeSeconds)

                    let shouldTraceFrame = (i == 0) || (i == (totalFrames - 1))
                    if shouldTraceFrame {
                        await trace.record(
                            "render.compile.begin",
                            fields: ["frame": String(i), "t": String(format: "%.6f", timeSeconds)]
                        )
                    }
                    let request = try await compiler.compile(timeline: timeline, at: renderTime, quality: quality)
                    if shouldTraceFrame {
                        await trace.record(
                            "render.compile.end",
                            fields: ["frame": String(i)]
                        )
                    }
                    
                    guard let pixelBufferPool = adaptor.pixelBufferPool else {
                         throw NSError(domain: "MetaVisExport", code: 2, userInfo: [NSLocalizedDescriptionKey: "No Pool"])
                    }
                    
                    var pixelBuffer: CVPixelBuffer?
                    CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &pixelBuffer)
                    
                    guard let buffer = pixelBuffer else {
                         throw NSError(domain: "MetaVisExport", code: 3, userInfo: [NSLocalizedDescriptionKey: "Buffer Alloc Failed"])
                    }
                    
                    // Render (Actor Call)

                    if shouldTraceFrame {
                        await trace.record("render.dispatch.begin", fields: ["frame": String(i)])
                    }
                    try await device.render(request: request, to: buffer, watermark: watermarkSpec)
                    if shouldTraceFrame {
                        await trace.record("render.dispatch.end", fields: ["frame": String(i)])
                    }
                    
                    if !adaptor.append(buffer, withPresentationTime: presentTime) {
                        throw writer.error ?? NSError(domain: "MetaVisExport", code: 4, userInfo: [NSLocalizedDescriptionKey: "Append Failed"])
                    }

                    appended += 1
                    
                    if i % 24 == 0 { 
                        let msg = "📹 Video Frame \(i)/\(totalFrames)\n"
                        if let d = msg.data(using: .utf8), let h = try? FileHandle(forWritingTo: URL(fileURLWithPath: "/tmp/metavis_debug.log")) { h.seekToEndOfFile(); h.write(d); try? h.close() }
                     }
                }
                input.markAsFinished()
                return ("video", appended)
            }

            for try await (kind, count) in group {
                if kind == "video" { videoCount = count }
                if kind == "audio" { audioCount = count }
            }
        }

        await trace.record(
            "render.video.end",
            fields: [
                "videoFrames": String(videoCount),
                "audioChunks": String(audioCount)
            ]
        )

        return ExportCounts(videoFramesAppended: videoCount, audioChunksAppended: audioCount)
    }

    // NOTE: audio inclusion is governed by AudioPolicy + TrackKind (.audio).
    
    // Helper: Convert AVAudioPCMBuffer -> CMSampleBuffer
    private static func createCMSampleBufferStatic(from buffer: AVAudioPCMBuffer, presentationTime: CMTime) -> CMSampleBuffer? {
        // Assume format is created correctly in Renderer
        let format = buffer.format.formatDescription
        
        // Data Size
        let frameCount = buffer.frameLength
        let channels = Int(buffer.format.channelCount)
        let bytesPerFrame = Int(buffer.format.streamDescription.pointee.mBytesPerFrame)
        let dataSize = Int(frameCount) * bytesPerFrame
        
        // 1. Create Block Buffer
        var blockBuffer: CMBlockBuffer?
        // Simple Copy: Get float data. But BlockBuffer usually expects interleaved or specific layout.
        // buffer.floatChannelData is non-interleaved (if > 1 channel).
        // If we want interleaved for export, we might need to interleave manually.
        // AVAssetWriter expects... depends on settings. But here we provide PCM samples.
        // Let's assume non-interleaved is fine if generic LPCM input? No, we are encoding to AAC.
        // Encoder usually handles format conversion.
        
        // Let's rely on CMSampleBufferCreate.
        // We need raw bytes.
        
        // Trick: CMSampleBuffer can be created from AudioBufferList directly with NO COPY if we are careful?
        // But AVAudioPCMBuffer owns the memory.
        
        // Let's implement a safe copy to CMBlockBuffer.
        
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: dataSize,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: dataSize,
            flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &blockBuffer
        )
        
        guard status == kCMBlockBufferNoErr, let bBuffer = blockBuffer else { return nil }
        
        // Copy Data
        if channels == 1 {
            // Mono: Simple memcpy
            if let ptr = buffer.floatChannelData?[0] {
                status = CMBlockBufferReplaceDataBytes(with: ptr, blockBuffer: bBuffer, offsetIntoDestination: 0, dataLength: dataSize)
            }
        } else {
            // Stereo (Non-Interleaved in PCMBuffer) -> Interleaved for BlockBuffer? 
            // Most CoreAudio formats are non-interleaved LPCM.
            // Let's assume we maintain non-interleaved? 
            // If the FormatDescription says non-interleaved (mFormatFlags include kAudioFormatFlagIsNonInterleaved), then we write accordingly?
            // AVAudioFormat usually standard is NonInterleaved.
            
            // To write non-interleaved to CMBlockBuffer is tricky (multiple buffers?).
            // Usually CMSampleBuffer wraps an AudioBufferList which points to memory.
            // Let's make a CMSampleBuffer that simply WRAPS the AudioBufferList from the PCMBuffer?
            // Danger: Lifetime of PCMBuffer vs SampleBuffer scope. 
            // Since we append immediately, it might be safe.
            
            return createReferenceSampleBuffer(buffer: buffer, time: presentationTime)
        }
        
        if status != kCMBlockBufferNoErr { return nil }
        
        // Create Sample Buffer
        var sampleBuffer: CMSampleBuffer?
        status = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: bBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: format,
            sampleCount: CMItemCount(frameCount),
            sampleTimingEntryCount: 1,
            sampleTimingArray: [CMSampleTimingInfo(duration: CMTime(value: 1, timescale: Int32(buffer.format.sampleRate)), presentationTimeStamp: presentationTime, decodeTimeStamp: .invalid)],
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        
        return sampleBuffer
    }
    
    // Safer wrap approach
    private static func createReferenceSampleBuffer(buffer: AVAudioPCMBuffer, time: CMTime) -> CMSampleBuffer? {
        var sampleBuffer: CMSampleBuffer?
        
        // 1. Create AudioBufferList
        // AVAudioPCMBuffer exposes .audioBufferList (UnsafePointer)
        // We can create a CMSampleBuffer from it.
        
        // We need timing
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: Int32(buffer.format.sampleRate)), presentationTimeStamp: time, decodeTimeStamp: .invalid)
        
        // This is complex in Swift due to Unsafe Pointer handling.
        // Fallback: Use CMAudioSampleBufferCreateWithPacketDescriptions if compressed? No, it's PCM.
        
        // SIMPLIFICATION: Interleave the data manually into a Data blob and make a BlockBuffer?
        // Yes, reliable.
        
        let frameCount = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        
        if channels == 2, let floatData = buffer.floatChannelData {
             let left = floatData[0]
             let right = floatData[1]
             
             // Create Interleaved Data [L, R, L, R...]
             var interleavedData = Data(count: frameCount * 2 * MemoryLayout<Float>.size)
             interleavedData.withUnsafeMutableBytes { ptr in
                 let raw = ptr.bindMemory(to: Float.self)
                 for i in 0..<frameCount {
                     raw[i*2] = left[i]
                     raw[i*2+1] = right[i]
                 }
             }
             
             // Create Format Desc for Interleaved 32-bit Float
             var desc: CMAudioFormatDescription?
             var asbd = AudioStreamBasicDescription(
                mSampleRate: buffer.format.sampleRate,
                mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, // No NonInterleaved flag
                mBytesPerPacket: 8, // 2 * Float
                mFramesPerPacket: 1,
                mBytesPerFrame: 8,
                mChannelsPerFrame: 2,
                mBitsPerChannel: 32,
                mReserved: 0
             )
             CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &desc)
             
             // Create Block Buffer
             var blockBuffer: CMBlockBuffer?
             let len = interleavedData.count
             
             // Use malloc'd memory or copy?
             // CMBlockBufferCreateWithMemoryBlock with copy
             
             interleavedData.withUnsafeBytes { ptr in
                  CMBlockBufferCreateWithMemoryBlock(
                    allocator: kCFAllocatorDefault,
                    memoryBlock: nil, // Internal alloc
                    blockLength: len,
                    blockAllocator: kCFAllocatorDefault,
                    customBlockSource: nil,
                    offsetToData: 0,
                    dataLength: len,
                    flags: 0,
                    blockBufferOut: &blockBuffer
                  )
                  
                  if let bb = blockBuffer {
                      CMBlockBufferReplaceDataBytes(with: ptr.baseAddress!, blockBuffer: bb, offsetIntoDestination: 0, dataLength: len)
                  }
             }
             
             guard let bb = blockBuffer, let fd = desc else { return nil }
             
             CMSampleBufferCreate(
                 allocator: kCFAllocatorDefault,
                 dataBuffer: bb,
                 dataReady: true,
                 makeDataReadyCallback: nil,
                 refcon: nil,
                 formatDescription: fd,
                 sampleCount: CMItemCount(frameCount),
                 sampleTimingEntryCount: 1,
                 sampleTimingArray: &timing,
                 sampleSizeEntryCount: 0,
                 sampleSizeArray: nil,
                 sampleBufferOut: &sampleBuffer
             )
             return sampleBuffer
        }
        
        return nil // Mono fallback or error
    }
}
