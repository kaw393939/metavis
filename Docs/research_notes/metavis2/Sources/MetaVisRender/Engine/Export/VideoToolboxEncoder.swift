//
//  VideoToolboxEncoder.swift
//  MetaVisRender
//
//  VTCompressionSession-based 10-bit HEVC encoder
//  Bypasses AVAssetWriter for true 10-bit encoding
//

import Foundation
import VideoToolbox
import CoreVideo
import CoreMedia
import AVFoundation

/// VideoToolbox-based encoder for true 10-bit HEVC output
/// Uses VTCompressionSession directly instead of AVAssetWriter
/// to avoid 8-bit downconversion issues
final class VideoToolboxEncoder {
    
    // MARK: - Configuration
    
    struct Config {
        let width: Int
        let height: Int
        let frameRate: Int
        let duration: CMTime
        let quality: Float  // 0.0-1.0
        let outputURL: URL
        
        init(width: Int, height: Int, frameRate: Int = 30, duration: CMTime, quality: Float = 0.95, outputURL: URL) {
            self.width = width
            self.height = height
            self.frameRate = frameRate
            self.duration = duration
            self.quality = quality
            self.outputURL = outputURL
        }
    }
    
    // MARK: - State
    
    private let config: Config
    private var session: VTCompressionSession?
    private var assetWriter: AVAssetWriter?
    private var assetWriterInput: AVAssetWriterInput?
    private var encodedFrames: [EncodedFrame] = []
    private var frameCount: Int = 0
    
    private struct EncodedFrame {
        let sampleBuffer: CMSampleBuffer
        let presentationTime: CMTime
    }
    
    // MARK: - Initialization
    
    init(config: Config) {
        self.config = config
    }
    
    // MARK: - Setup
    
    func prepare() throws {
        print("🎬 VideoToolboxEncoder: Preparing VTCompressionSession")
        print("   Resolution: \(config.width)x\(config.height) @ \(config.frameRate)fps")
        print("   Format: HEVC Main 10 (true 10-bit)")
        print("   Quality: \(config.quality)")
        
        // Create compression session
        var compressionSession: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(config.width),
            height: Int32(config.height),
            codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: [
                kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: kCFBooleanTrue
            ] as CFDictionary,
            imageBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
                kCVPixelBufferWidthKey as String: config.width,
                kCVPixelBufferHeightKey as String: config.height,
                kCVPixelBufferMetalCompatibilityKey as String: true
            ] as CFDictionary,
            compressedDataAllocator: nil,
            outputCallback: compressionCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &compressionSession
        )
        
        guard status == noErr, let session = compressionSession else {
            print("❌ VideoToolboxEncoder: Failed to create VTCompressionSession: \(status)")
            throw VideoToolboxEncoderError.sessionCreationFailed(status)
        }
        
        self.session = session
        
        // Configure session properties
        try configureSession(session)
        
        // Prepare session
        VTCompressionSessionPrepareToEncodeFrames(session)
        
        print("✅ VideoToolboxEncoder: VTCompressionSession ready")
    }
    
    private func configureSession(_ session: VTCompressionSession) throws {
        // Profile and level (Main 10 for 10-bit)
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_ProfileLevel,
            value: kVTProfileLevel_HEVC_Main10_AutoLevel
        )
        
        // Quality
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_Quality,
            value: config.quality as CFNumber
        )
        
        // Frame rate
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_ExpectedFrameRate,
            value: config.frameRate as CFNumber
        )
        
        // No frame reordering (simplifies muxing)
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_AllowFrameReordering,
            value: kCFBooleanFalse
        )
        
        // Real-time encoding off (prioritize quality)
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_RealTime,
            value: kCFBooleanFalse
        )
        
        // Color properties for Rec.2020 (HDR-ready)
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_ColorPrimaries,
            value: kCVImageBufferColorPrimaries_ITU_R_2020 as CFString
        )
        
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_TransferFunction,
            value: kCVImageBufferTransferFunction_ITU_R_709_2 as CFString  // SDR for now
        )
        
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_YCbCrMatrix,
            value: kCVImageBufferYCbCrMatrix_ITU_R_2020 as CFString
        )
        
        print("✅ VideoToolboxEncoder: Session configured")
        print("   Profile: HEVC Main 10")
        print("   Color: BT.2020 primaries, BT.709 transfer, BT.2020 matrix")
    }
    
    // MARK: - Encoding
    
    func encode(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) throws {
        guard let session = session else {
            throw VideoToolboxEncoderError.sessionNotPrepared
        }
        
        // Encode frame
        let duration = CMTime(value: 1, timescale: CMTimeScale(config.frameRate))
        
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTime,
            duration: duration,
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )
        
        guard status == noErr else {
            print("❌ VideoToolboxEncoder: Frame encoding failed: \(status)")
            throw VideoToolboxEncoderError.encodingFailed(status)
        }
        
        frameCount += 1
    }
    
    // MARK: - Finalization
    
    func finish() async throws {
        guard let session = session else {
            throw VideoToolboxEncoderError.sessionNotPrepared
        }
        
        print("🎬 VideoToolboxEncoder: Finishing compression...")
        
        // Complete encoding
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        
        // Invalidate session
        VTCompressionSessionInvalidate(session)
        self.session = nil
        
        print("✅ VideoToolboxEncoder: Compression complete (\(frameCount) frames)")
        print("   Encoded frames collected: \(encodedFrames.count)")
        
        // Mux to container
        try await muxToContainer()
    }
    
    private func muxToContainer() async throws {
        print("🎬 VideoToolboxEncoder: Muxing \(encodedFrames.count) frames to container...")
        
        guard !encodedFrames.isEmpty else {
            throw VideoToolboxEncoderError.noEncodedFrames
        }
        
        // Sort by presentation time
        let sortedFrames = encodedFrames.sorted { $0.presentationTime < $1.presentationTime }
        
        // Create AVAssetWriter for muxing (passthrough mode)
        let writer = try AVAssetWriter(outputURL: config.outputURL, fileType: .mov)
        
        // Get format description from first frame
        guard let formatDesc = CMSampleBufferGetFormatDescription(sortedFrames[0].sampleBuffer) else {
            throw VideoToolboxEncoderError.invalidSampleBuffer
        }
        
        // Create writer input with passthrough settings
        let writerInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: nil,  // Passthrough - no re-encoding!
            sourceFormatHint: formatDesc
        )
        writerInput.expectsMediaDataInRealTime = false
        
        guard writer.canAdd(writerInput) else {
            throw VideoToolboxEncoderError.cannotAddInput
        }
        
        writer.add(writerInput)
        
        guard writer.startWriting() else {
            throw VideoToolboxEncoderError.cannotStartWriting
        }
        
        writer.startSession(atSourceTime: .zero)
        
        // Append all frames
        var appendedCount = 0
        for frame in sortedFrames {
            // Wait for input to be ready
            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            
            if writerInput.append(frame.sampleBuffer) {
                appendedCount += 1
            } else {
                print("⚠️ VideoToolboxEncoder: Failed to append frame \(appendedCount)")
            }
        }
        
        print("✅ VideoToolboxEncoder: Appended \(appendedCount)/\(sortedFrames.count) frames")
        
        // Finish writing
        writerInput.markAsFinished()
        await writer.finishWriting()
        
        if writer.status == .completed {
            print("✅ VideoToolboxEncoder: Muxing complete")
            print("   Output: \(config.outputURL.path)")
            
            // Validate output
            try await validateOutput()
        } else if let error = writer.error {
            print("❌ VideoToolboxEncoder: Muxing failed: \(error.localizedDescription)")
            throw VideoToolboxEncoderError.muxingFailed(error)
        }
    }
    
    private func validateOutput() async throws {
        // Run ffprobe to validate 10-bit output
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["ffprobe"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                // ffprobe available, check output
                let ffprobeProcess = Process()
                ffprobeProcess.executableURL = URL(fileURLWithPath: "/usr/local/bin/ffprobe")
                ffprobeProcess.arguments = [
                    "-v", "error",
                    "-select_streams", "v:0",
                    "-show_entries", "stream=codec_name,profile,pix_fmt,width,height",
                    "-of", "default=noprint_wrappers=1",
                    config.outputURL.path
                ]
                
                let outputPipe = Pipe()
                ffprobeProcess.standardOutput = outputPipe
                
                try ffprobeProcess.run()
                ffprobeProcess.waitUntilExit()
                
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    print("📊 VideoToolboxEncoder: Output validation:")
                    print(output)
                    
                    if output.contains("yuv420p10le") {
                        print("✅ TRUE 10-BIT OUTPUT CONFIRMED!")
                    } else if output.contains("yuv420p") {
                        print("⚠️ WARNING: Output is 8-bit (yuv420p), not 10-bit!")
                    }
                }
            }
        } catch {
            // ffprobe not available, skip validation
            print("ℹ️ VideoToolboxEncoder: ffprobe not available, skipping validation")
        }
    }
    
    // MARK: - Compression Callback
    
    private let compressionCallback: VTCompressionOutputCallback = { (
        outputCallbackRefCon: UnsafeMutableRawPointer?,
        sourceFrameRefCon: UnsafeMutableRawPointer?,
        status: OSStatus,
        infoFlags: VTEncodeInfoFlags,
        sampleBuffer: CMSampleBuffer?
    ) in
        guard status == noErr,
              let sampleBuffer = sampleBuffer,
              let refCon = outputCallbackRefCon else {
            print("❌ VideoToolboxEncoder: Compression callback error: \(status)")
            return
        }
        
        let encoder = Unmanaged<VideoToolboxEncoder>.fromOpaque(refCon).takeUnretainedValue()
        
        // Get presentation time
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        // Store encoded frame
        let frame = EncodedFrame(sampleBuffer: sampleBuffer, presentationTime: pts)
        encoder.encodedFrames.append(frame)
        
        // Debug first frame
        if encoder.encodedFrames.count == 1 {
            if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
                let mediaType = CMFormatDescriptionGetMediaType(formatDesc)
                let codecType = CMFormatDescriptionGetMediaSubType(formatDesc)
                
                let codecString = String(format: "%c%c%c%c",
                    (codecType >> 24) & 0xFF,
                    (codecType >> 16) & 0xFF,
                    (codecType >> 8) & 0xFF,
                    codecType & 0xFF
                )
                
                print("✅ First frame encoded:")
                print("   Media type: \(mediaType)")
                print("   Codec: \(codecString)")
                print("   PTS: \(pts.seconds)s")
            }
        }
    }
}

// MARK: - Errors

enum VideoToolboxEncoderError: Error, LocalizedError {
    case sessionCreationFailed(OSStatus)
    case sessionNotPrepared
    case encodingFailed(OSStatus)
    case noEncodedFrames
    case invalidSampleBuffer
    case cannotAddInput
    case cannotStartWriting
    case muxingFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .sessionCreationFailed(let status):
            return "Failed to create VTCompressionSession: \(status)"
        case .sessionNotPrepared:
            return "Compression session not prepared"
        case .encodingFailed(let status):
            return "Frame encoding failed: \(status)"
        case .noEncodedFrames:
            return "No encoded frames to mux"
        case .invalidSampleBuffer:
            return "Invalid sample buffer"
        case .cannotAddInput:
            return "Cannot add input to asset writer"
        case .cannotStartWriting:
            return "Cannot start writing to output file"
        case .muxingFailed(let error):
            return "Muxing failed: \(error.localizedDescription)"
        }
    }
}
