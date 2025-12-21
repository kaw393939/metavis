import AVFoundation
import CoreImage
import CoreVideo
import Foundation
import Logging
@preconcurrency import Metal

/// Video encoder using AVFoundation
public actor VideoEncoder {
    private let logger: Logger

    public init() {
        var logger = Logger(label: "com.metalvis.encoder")
        logger.logLevel = .info
        self.logger = logger
    }

    public nonisolated func encode(
        frames: AsyncStream<MTLTexture>,
        outputURL: URL,
        width: Int,
        height: Int,
        frameRate: Int,
        codec: String,
        quality: String,
        colorSpace: String = "rec709"
    ) async throws {
        var logger = Logger(label: "com.metalvis.encoder")
        logger.logLevel = .info

        logger.info("Starting video encoding", metadata: [
            "output": "\(outputURL.path)",
            "resolution": "\(width)x\(height)",
            "fps": "\(frameRate)",
            "colorSpace": "\(colorSpace)"
        ])

        // Remove existing file if present
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        // Create asset writer
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        // Determine Color Properties
        let colorPrimaries: String
        let transferFunction: String
        let ycbcrMatrix: String

        if colorSpace.lowercased() == "srgb" {
            colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
            transferFunction = "IEC_sRGB"
            ycbcrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        } else {
            // Default to Rec.709
            colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
            transferFunction = AVVideoTransferFunction_ITU_R_709_2
            ycbcrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        }

        // Configure video settings based on codec
        let videoSettings: [String: Any]
        let compressionProperties: [String: Any] = [
            AVVideoAverageBitRateKey: calculateBitrate(width: width, height: height, frameRate: frameRate, quality: quality),
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            AVVideoColorPrimariesKey: colorPrimaries,
            AVVideoTransferFunctionKey: transferFunction,
            AVVideoYCbCrMatrixKey: ycbcrMatrix
        ]

        switch codec.lowercased() {
        case "h264":
            videoSettings = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: compressionProperties
            ]
        case "h265", "hevc":
            var hevcProperties = compressionProperties
            hevcProperties.removeValue(forKey: AVVideoProfileLevelKey)
            videoSettings = [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: hevcProperties
            ]
        case "prores":
            videoSettings = [
                AVVideoCodecKey: AVVideoCodecType.proRes4444,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoColorPropertiesKey: [
                    AVVideoColorPrimariesKey: colorPrimaries,
                    AVVideoTransferFunctionKey: transferFunction,
                    AVVideoYCbCrMatrixKey: ycbcrMatrix
                ]
            ]
        default:
            videoSettings = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: compressionProperties
            ]
        }

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let pixelFormat: OSType = codec.lowercased().contains("prores") ? kCVPixelFormatType_64RGBAHalf : kCVPixelFormatType_32BGRA

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(pixelFormat),
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
        )

        writer.add(writerInput)

        guard writer.startWriting() else {
            throw EncoderError.cannotStartWriting(writer.error?.localizedDescription ?? "Unknown error")
        }

        writer.startSession(atSourceTime: .zero)

        // Write frames
        var frameNumber = 0

        for await texture in frames {
            // Wait for input to be ready
            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(10))
            }

            let presentationTime = CMTime(value: CMTimeValue(frameNumber), timescale: CMTimeScale(frameRate))

            if let pixelBuffer = TextureUtils.textureToPixelBuffer(texture, width: width, height: height, colorSpace: colorSpace) {
                guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                    throw EncoderError.cannotAppendFrame(frameNumber)
                }
                frameNumber += 1
            }
        }

        // Finish writing
        writerInput.markAsFinished()
        await writer.finishWriting()

        if writer.status == .failed {
            throw EncoderError.writingFailed(writer.error?.localizedDescription ?? "Unknown error")
        }

        logger.info("Video encoding completed", metadata: [
            "frames": "\(frameNumber)",
            "output": "\(outputURL.path)"
        ])
    }

    public nonisolated func encodeFromPixelBuffers(
        frames: AsyncStream<CVPixelBuffer>,
        outputURL: URL,
        width: Int,
        height: Int,
        frameRate: Int,
        codec: String,
        quality: String
    ) async throws {
        var logger = Logger(label: "com.metalvis.encoder")
        logger.logLevel = .info

        logger.info("Starting video encoding from pixel buffers", metadata: [
            "output": "\(outputURL.path)",
            "resolution": "\(width)x\(height)",
            "fps": "\(frameRate)"
        ])

        // Remove existing file if present
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        // Create asset writer
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        // Configure video settings
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: calculateBitrate(width: width, height: height, frameRate: frameRate, quality: quality),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let pixelFormat: OSType = codec.lowercased().contains("prores") ? kCVPixelFormatType_64RGBAHalf : kCVPixelFormatType_32BGRA

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(pixelFormat),
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
        )

        writer.add(writerInput)

        guard writer.startWriting() else {
            throw EncoderError.cannotStartWriting(writer.error?.localizedDescription ?? "Unknown error")
        }

        writer.startSession(atSourceTime: .zero)

        // Write frames directly from pixel buffers
        var frameNumber = 0

        for await pixelBuffer in frames {
            // Wait for input to be ready
            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(10))
            }

            let presentationTime = CMTime(value: CMTimeValue(frameNumber), timescale: CMTimeScale(frameRate))

            guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                throw EncoderError.cannotAppendFrame(frameNumber)
            }
            frameNumber += 1
        }

        // Finish writing
        writerInput.markAsFinished()
        await writer.finishWriting()

        if writer.status == .failed {
            throw EncoderError.writingFailed(writer.error?.localizedDescription ?? "Unknown error")
        }

        logger.info("Video encoding completed", metadata: [
            "frames": "\(frameNumber)",
            "output": "\(outputURL.path)"
        ])
    }

    public nonisolated func encodeMixedMedia(
        videoFrames: AsyncStream<SendablePixelBuffer>,
        audioBuffers: AsyncStream<SendableAudioBuffer>,
        outputURL: URL,
        width: Int,
        height: Int,
        frameRate: Int,
        audioFormat: AVAudioFormat,
        codec: String = "h264",
        quality: String = "high",
        colorSpace: String = "rec709"
    ) async throws {
        var logger = Logger(label: "com.metalvis.encoder")
        logger.logLevel = .info

        logger.info("Starting mixed media encoding", metadata: [
            "output": "\(outputURL.path)",
            "resolution": "\(width)x\(height)",
            "fps": "\(frameRate)",
            "colorSpace": "\(colorSpace)"
        ])

        // Remove existing file if present
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        // Create asset writer
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        writer.movieFragmentInterval = CMTime(value: 1, timescale: 1) // Write fragments every 1 second for better interleaving/recovery

        // Determine Color Properties
        let colorPrimaries: String
        let transferFunction: String
        let ycbcrMatrix: String

        if colorSpace.lowercased() == "srgb" {
            colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
            transferFunction = "IEC_sRGB"
            ycbcrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        } else {
            // Default to Rec.709
            colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
            transferFunction = AVVideoTransferFunction_ITU_R_709_2
            ycbcrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        }

        // 1. Configure Video Input
        let videoSettings: [String: Any]
        let compressionProperties: [String: Any] = [
            AVVideoAverageBitRateKey: calculateBitrate(width: width, height: height, frameRate: frameRate, quality: quality),
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            AVVideoColorPrimariesKey: colorPrimaries,
            AVVideoTransferFunctionKey: transferFunction,
            AVVideoYCbCrMatrixKey: ycbcrMatrix
        ]

        switch codec.lowercased() {
        case "h264":
            videoSettings = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: compressionProperties
            ]
        case "h265", "hevc":
            var hevcProperties = compressionProperties
            hevcProperties.removeValue(forKey: AVVideoProfileLevelKey)
            videoSettings = [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: hevcProperties
            ]
        case "prores":
            videoSettings = [
                AVVideoCodecKey: AVVideoCodecType.proRes4444,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoColorPropertiesKey: [
                    AVVideoColorPrimariesKey: colorPrimaries,
                    AVVideoTransferFunctionKey: transferFunction,
                    AVVideoYCbCrMatrixKey: ycbcrMatrix
                ]
            ]
        default:
            videoSettings = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: compressionProperties
            ]
        }

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false

        let pixelFormat: OSType = codec.lowercased().contains("prores") ? kCVPixelFormatType_64RGBAHalf : kCVPixelFormatType_32BGRA

        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(pixelFormat),
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
        )

        if writer.canAdd(videoInput) {
            writer.add(videoInput)
        } else {
            throw EncoderError.cannotStartWriting("Cannot add video input")
        }

        // 2. Configure Audio Input
        // We use the format from the buffer, but we need to specify output settings (AAC usually)
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: audioFormat.channelCount,
            AVSampleRateKey: audioFormat.sampleRate,
            AVEncoderBitRateKey: 128_000
        ]

        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = false

        if writer.canAdd(audioInput) {
            writer.add(audioInput)
        } else {
            throw EncoderError.cannotStartWriting("Cannot add audio input")
        }

        // 3. Start Writing
        guard writer.startWriting() else {
            throw EncoderError.cannotStartWriting(writer.error?.localizedDescription ?? "Unknown error")
        }

        writer.startSession(atSourceTime: .zero)

        // 4. Process Streams Concurrently

        let context = WriterContext(videoInput: videoInput, audioInput: audioInput, adaptor: pixelBufferAdaptor)

        // Start Audio Task
        let audioTask = Task {
            var totalSamples: AVAudioFramePosition = 0

            for await bufferWrapper in audioBuffers {
                let buffer = bufferWrapper.buffer
                while !context.audioInput.isReadyForMoreMediaData {
                    try await Task.sleep(for: .milliseconds(5))
                }

                // Convert AVAudioPCMBuffer to CMSampleBuffer
                if let sampleBuffer = Self.createSampleBuffer(from: buffer, offset: totalSamples) {
                    if context.audioInput.isReadyForMoreMediaData {
                        if !context.audioInput.append(sampleBuffer) {
                            print("⚠️ Failed to append audio buffer")
                        }
                    } else {
                        print("⚠️ Audio input not ready")
                    }
                } else {
                    print("⚠️ Failed to create CMSampleBuffer from audio buffer")
                }
                totalSamples += AVAudioFramePosition(buffer.frameLength)
            }
            print("✅ Audio Encoding Task Finished. Total samples: \(totalSamples)")
            context.audioInput.markAsFinished()
        }

        // Run Video Task in current context
        var frameNumber = 0
        for await pixelBufferWrapper in videoFrames {
            let pixelBuffer = pixelBufferWrapper.buffer
            while !context.videoInput.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }

            let presentationTime = CMTime(value: CMTimeValue(frameNumber), timescale: CMTimeScale(frameRate))

            if !context.adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
                throw EncoderError.cannotAppendFrame(frameNumber)
            }
            frameNumber += 1
        }
        context.videoInput.markAsFinished()

        // Wait for audio to finish
        _ = try? await audioTask.value

        await writer.finishWriting()

        if writer.status == .failed {
            throw EncoderError.writingFailed(writer.error?.localizedDescription ?? "Unknown error")
        }

        logger.info("Mixed media encoding completed", metadata: [
            "output": "\(outputURL.path)"
        ])
    }

    /// Helper to create CMSampleBuffer from AVAudioPCMBuffer
    private static func createSampleBuffer(from buffer: AVAudioPCMBuffer, offset: AVAudioFramePosition) -> CMSampleBuffer? {
        let audioBufferList = buffer.audioBufferList
        let asbd = buffer.format.streamDescription

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(asbd.pointee.mSampleRate)),
            presentationTimeStamp: CMTime(value: CMTimeValue(offset), timescale: CMTimeScale(asbd.pointee.mSampleRate)),
            decodeTimeStamp: .invalid
        )

        var formatDescription: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )

        guard let formatDesc = formatDescription else { return nil }

        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDesc,
            sampleCount: CMItemCount(buffer.frameLength),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )

        guard let sBuffer = sampleBuffer else { return nil }

        // Copy data
        CMSampleBufferSetDataBufferFromAudioBufferList(
            sBuffer,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            bufferList: audioBufferList
        )

        return sBuffer
    }

    private nonisolated func calculateBitrate(width: Int, height: Int, frameRate: Int, quality: String) -> Int {
        let pixels = width * height
        // Base bits per pixel (bpp)
        let bpp: Double

        switch quality.lowercased() {
        case "low":
            bpp = 0.1
        case "medium":
            bpp = 0.2
        case "high":
            bpp = 0.4 // Increased for better quality (approx 25Mbps for 1080p30)
        case "lossless":
            bpp = 1.0
        default:
            bpp = 0.25
        }

        // Calculate bits per second: Pixels * BitsPerPixel * FramesPerSecond
        let bitrate = Double(pixels) * bpp * Double(frameRate)
        return Int(bitrate)
    }

    // textureToPixelBuffer moved to TextureUtils for reuse
}

private struct WriterContext: @unchecked Sendable {
    let videoInput: AVAssetWriterInput
    let audioInput: AVAssetWriterInput
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
}

public enum EncoderError: Error {
    case cannotStartWriting(String)
    case cannotAppendFrame(Int)
    case writingFailed(String)
}

public struct SendablePixelBuffer: @unchecked Sendable {
    public let buffer: CVPixelBuffer
    public init(_ buffer: CVPixelBuffer) { self.buffer = buffer }
}

public struct SendableAudioBuffer: @unchecked Sendable {
    public let buffer: AVAudioPCMBuffer
    public init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
}
