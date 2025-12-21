import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import Metal
import VideoToolbox

// MARK: - VideoDecoderError

/// Errors that can occur during video decoding.
public enum VideoDecoderError: Error, Sendable {
    case fileNotFound(URL)
    case noVideoTrack
    case readerCreationFailed(Error)
    case unsupportedFormat(String)
    case seekFailed
    case decodeFailed(Error?)
    case endOfFile
    case textureCacheCreationFailed
    case textureCreationFailed
    case cancelled
}

extension VideoDecoderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "Video file not found: \(url.path)"
        case .noVideoTrack:
            return "No video track found in asset"
        case .readerCreationFailed(let error):
            return "Failed to create asset reader: \(error.localizedDescription)"
        case .unsupportedFormat(let format):
            return "Unsupported video format: \(format)"
        case .seekFailed:
            return "Failed to seek to requested time"
        case .decodeFailed(let error):
            return "Failed to decode frame: \(error?.localizedDescription ?? "Unknown error")"
        case .endOfFile:
            return "Reached end of video file"
        case .textureCacheCreationFailed:
            return "Failed to create Metal texture cache"
        case .textureCreationFailed:
            return "Failed to create Metal texture from frame"
        case .cancelled:
            return "Decoding was cancelled"
        }
    }
}

// MARK: - VideoDecoderConfig

/// Configuration for the video decoder.
public struct VideoDecoderConfig: Sendable {
    /// Whether to use CVMetalTextureCache for zero-copy texture conversion.
    public let useTextureCache: Bool
    
    /// Preferred output pixel format.
    public let outputPixelFormat: OSType
    
    /// Whether to enable hardware acceleration.
    public let enableHardwareAcceleration: Bool
    
    /// Maximum number of frames to buffer ahead.
    public let prefetchCount: Int
    
    /// Whether to decode audio track (for future use).
    public let decodeAudio: Bool
    
    /// Target output resolution (nil = use source resolution)
    /// Enables efficient downscaling at decode time
    public let targetResolution: SIMD2<Int>?
    
    /// Whether to enable decode-ahead buffering for pipeline parallelism
    public let enableDecodeAhead: Bool
    
    /// Number of frames to decode ahead (when enableDecodeAhead is true)
    public let decodeAheadCount: Int
    
    public init(
        useTextureCache: Bool = true,
        outputPixelFormat: OSType = kCVPixelFormatType_32BGRA,
        enableHardwareAcceleration: Bool = true,
        prefetchCount: Int = 3,
        decodeAudio: Bool = false,
        targetResolution: SIMD2<Int>? = nil,
        enableDecodeAhead: Bool = false,
        decodeAheadCount: Int = 3
    ) {
        self.useTextureCache = useTextureCache
        self.outputPixelFormat = outputPixelFormat
        self.enableHardwareAcceleration = enableHardwareAcceleration
        self.prefetchCount = prefetchCount
        self.decodeAudio = decodeAudio
        self.targetResolution = targetResolution
        self.enableDecodeAhead = enableDecodeAhead
        self.decodeAheadCount = decodeAheadCount
    }
    
    /// Default configuration optimized for realtime playback.
    public static let realtime = VideoDecoderConfig(
        useTextureCache: true,
        prefetchCount: 5,
        enableDecodeAhead: true,
        decodeAheadCount: 3
    )
    
    /// Configuration optimized for export/render.
    public static let export = VideoDecoderConfig(
        useTextureCache: true,
        outputPixelFormat: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
        prefetchCount: 2,
        enableDecodeAhead: true,
        decodeAheadCount: 2
    )
    
    /// Configuration with resolution scaling for efficiency.
    public static func scaled(to resolution: SIMD2<Int>) -> VideoDecoderConfig {
        VideoDecoderConfig(
            useTextureCache: true,
            prefetchCount: 3,
            targetResolution: resolution,
            enableDecodeAhead: true,
            decodeAheadCount: 2
        )
    }
}

// MARK: - VideoDecoder

/// Actor for decoding video frames from a file to GPU textures.
///
/// `VideoDecoder` provides efficient video decoding using AVFoundation and VideoToolbox:
/// - Hardware-accelerated decoding on Apple Silicon
/// - Zero-copy texture conversion via CVMetalTextureCache
/// - Seeking to arbitrary timestamps
/// - Sequential frame access
///
/// ## Example Usage
/// ```swift
/// let decoder = try await VideoDecoder(url: videoURL, device: device)
/// 
/// // Sequential access
/// while let frame = try await decoder.nextFrame() {
///     let texture = decoder.texture(from: frame)
///     // Render frame...
/// }
/// 
/// // Random access
/// let frame = try await decoder.frame(at: CMTime.seconds(5.0))
/// ```
public actor VideoDecoder {
    
    // MARK: - Properties
    
    /// The video source URL.
    public let url: URL
    
    /// Metal device for texture creation.
    public let device: MTLDevice
    
    /// Command queue for GPU operations (reused across frames)
    private let commandQueue: MTLCommandQueue
    
    /// Decoder configuration.
    public let config: VideoDecoderConfig
    
    /// Video metadata.
    public private(set) var metadata: VideoMetadata!
    
    // Computed properties from metadata
    public var resolution: SIMD2<Int> { metadata.resolution }
    public var frameRate: Double { metadata.frameRate }
    public var duration: CMTime { metadata.duration }
    public var codec: String { metadata.codec }
    
    // MARK: - Private Properties
    
    private let asset: AVAsset
    private var assetReader: AVAssetReader?
    private var trackOutput: AVAssetReaderTrackOutput?
    private var videoTrack: AVAssetTrack?
    
    private var textureCache: CVMetalTextureCache?
    private var yuvConversionPipeline: MTLComputePipelineState?
    
    private var currentFrameNumber: Int = 0
    private var currentTime: CMTime = .zero
    private var isAtEnd: Bool = false
    
    // MARK: - Decode-Ahead Buffer
    
    /// Pre-decoded frames buffer for pipeline parallelism
    private var decodeAheadBuffer: [DecodedFrame] = []
    
    /// Whether the decode-ahead task is running
    private var isDecodeAheadActive: Bool = false
    
    // MARK: - Initialization
    
    /// Creates a video decoder for the specified file.
    ///
    /// - Parameters:
    ///   - url: URL of the video file.
    ///   - device: Metal device for texture creation.
    ///   - config: Decoder configuration.
    /// - Throws: `VideoDecoderError` if the file cannot be opened or has no video track.
    public init(
        url: URL,
        device: MTLDevice,
        config: VideoDecoderConfig = VideoDecoderConfig()
    ) async throws {
        self.url = url
        self.device = device
        self.config = config
        
        // Create reusable command queue
        guard let queue = device.makeCommandQueue() else {
            throw VideoDecoderError.textureCacheCreationFailed
        }
        self.commandQueue = queue
        
        // Verify file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VideoDecoderError.fileNotFound(url)
        }
        
        // Create asset
        self.asset = AVURLAsset(url: url)
        
        // Load tracks and extract metadata
        try await loadAsset()
        
        // Create texture cache
        if config.useTextureCache {
            try createTextureCache()
        }
        
        // Initialize reader
        try await initializeReader(from: .zero)
    }
    
    // MARK: - Public Methods
    
    /// Decodes and returns the next frame in sequence.
    ///
    /// - Returns: The next decoded frame, or nil if at end of file.
    /// - Throws: `VideoDecoderError` if decoding fails.
    public func nextFrame() throws -> DecodedFrame? {
        // Check decode-ahead buffer first
        if config.enableDecodeAhead && !decodeAheadBuffer.isEmpty {
            let frame = decodeAheadBuffer.removeFirst()
            currentFrameNumber = frame.frameNumber + 1
            currentTime = frame.presentationTime
            
            // Refill buffer in background
            fillDecodeAheadBuffer()
            
            return frame
        }
        
        // Direct decode path
        return try decodeNextFrameInternal()
    }
    
    /// Internal frame decode without buffer management
    private func decodeNextFrameInternal() throws -> DecodedFrame? {
        guard !isAtEnd else { return nil }
        
        guard let output = trackOutput else {
            throw VideoDecoderError.decodeFailed(nil)
        }
        
        // Read next sample buffer
        guard let sampleBuffer = output.copyNextSampleBuffer() else {
            if assetReader?.status == .completed {
                isAtEnd = true
                return nil
            } else if let error = assetReader?.error {
                throw VideoDecoderError.decodeFailed(error)
            }
            isAtEnd = true
            return nil
        }
        
        // Extract pixel buffer
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw VideoDecoderError.decodeFailed(nil)
        }
        
        // Extract timing
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let durationVal = CMSampleBufferGetDuration(sampleBuffer)
        let decodeTime = CMSampleBufferGetDecodeTimeStamp(sampleBuffer)
        
        // Check for keyframe
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]]
        let isKeyframe = attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool != true
        
        let frame = DecodedFrame(
            pixelBuffer: imageBuffer,
            presentationTime: presentationTime,
            duration: durationVal.isValid ? durationVal : CMTime(value: 1, timescale: CMTimeScale(frameRate)),
            decodeTime: decodeTime.isValid ? decodeTime : presentationTime,
            isKeyframe: isKeyframe,
            frameNumber: currentFrameNumber
        )
        
        currentFrameNumber += 1
        currentTime = presentationTime
        
        return frame
    }
    
    /// Fills the decode-ahead buffer up to the configured count
    private func fillDecodeAheadBuffer() {
        guard config.enableDecodeAhead && !isAtEnd else { return }
        
        while decodeAheadBuffer.count < config.decodeAheadCount {
            do {
                if let frame = try decodeNextFrameInternal() {
                    decodeAheadBuffer.append(frame)
                } else {
                    break // End of file
                }
            } catch {
                break // Stop on error
            }
        }
    }
    
    /// Pre-fills the decode-ahead buffer (call after seek or initialization)
    public func primeDecodeAhead() {
        guard config.enableDecodeAhead else { return }
        decodeAheadBuffer.removeAll()
        fillDecodeAheadBuffer()
    }
    
    /// Decodes a frame at the specified time.
    ///
    /// - Parameter time: The target time.
    /// - Returns: The frame at or near the requested time.
    /// - Throws: `VideoDecoderError` if seeking or decoding fails.
    public func frame(at time: CMTime) async throws -> DecodedFrame? {
        try await seek(to: time)
        return try nextFrame()
    }
    
    /// Seeks to the specified time.
    ///
    /// - Parameter time: The target time.
    /// - Throws: `VideoDecoderError.seekFailed` if seeking is not possible.
    public func seek(to time: CMTime) async throws {
        // Validate time is within bounds
        guard time >= .zero && time <= duration else {
            throw VideoDecoderError.seekFailed
        }
        
        // Clear decode-ahead buffer on seek
        decodeAheadBuffer.removeAll()
        
        // Re-initialize reader at new position
        try await initializeReader(from: time)
        
        currentTime = time
        currentFrameNumber = Int((time.seconds * frameRate).rounded())
        isAtEnd = false
        
        // Prime decode-ahead buffer after seek
        primeDecodeAhead()
    }
    
    /// Resets the decoder to the beginning of the video.
    public func reset() async throws {
        try await seek(to: .zero)
    }
    
    /// Closes the decoder and releases resources.
    public func close() {
        assetReader?.cancelReading()
        assetReader = nil
        trackOutput = nil
        textureCache = nil
        isAtEnd = true
    }
    
    // MARK: - Texture Conversion
    
    /// Converts a decoded frame to a Metal texture.
    ///
    /// This is a nonisolated method that can be called from any context.
    /// It uses the texture cache that was set up during initialization.
    ///
    /// - Parameter frame: The decoded frame.
    /// - Returns: A Metal texture, or nil if conversion fails.
    public nonisolated func texture(from frame: DecodedFrame) -> MTLTexture? {
        // Fall back to manual texture creation (no cache access from nonisolated)
        return textureFromPixelBuffer(frame.pixelBuffer)
    }
    
    /// Converts a decoded frame to a Metal texture using the texture cache.
    ///
    /// This actor-isolated method provides zero-copy texture conversion when possible.
    ///
    /// - Parameter frame: The decoded frame.
    /// - Returns: A Metal texture, or nil if conversion fails.
    public func textureWithCache(from frame: DecodedFrame) -> MTLTexture? {
        // DEBUG: Force white texture
        let width = CVPixelBufferGetWidth(frame.pixelBuffer)
        let height = CVPixelBufferGetHeight(frame.pixelBuffer)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        
        // Fill with white
        let region = MTLRegionMake2D(0, 0, width, height)
        let whitePixel: UInt32 = 0xFFFFFFFF
        var whitePixels = [UInt32](repeating: whitePixel, count: width * height)
        texture.replace(region: region, mipmapLevel: 0, withBytes: &whitePixels, bytesPerRow: width * 4)
        
        return texture
        /*
        // Use texture cache for zero-copy if available
        if let cache = textureCache {
            return textureFromCache(pixelBuffer: frame.pixelBuffer, cache: cache)
        }
        
        // Fall back to manual texture creation
        return textureFromPixelBuffer(frame.pixelBuffer)
        */
    }
    
    /// Async version using non-blocking GPU texture copy.
    /// Preferred for high-performance pipelines to avoid CPU stalls.
    ///
    /// - Parameter frame: The decoded frame.
    /// - Returns: A Metal texture, or nil if conversion fails.
    public func textureWithCacheAsync(from frame: DecodedFrame) async -> MTLTexture? {
        // Use texture cache for zero-copy if available
        if let cache = textureCache {
            return await textureFromCacheAsync(pixelBuffer: frame.pixelBuffer, cache: cache)
        }
        
        // Fall back to manual texture creation
        return textureFromPixelBuffer(frame.pixelBuffer)
    }
    
    /// Async version of textureFromCache using non-blocking GPU copy
    private func textureFromCacheAsync(pixelBuffer: CVPixelBuffer, cache: CVMetalTextureCache) async -> MTLTexture? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        
        // Handle 10-bit YUV (HEVC HDR/10-bit)
        if pixelFormat == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange {
            return convertYUVToRGB(pixelBuffer, width: width, height: height)
        }
        
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )
        
        guard status == kCVReturnSuccess, let cvTex = cvTexture,
              let sourceTexture = CVMetalTextureGetTexture(cvTex) else {
            return nil
        }
        
        // Use async copy to avoid CPU stall
        return await copyTextureAsync(sourceTexture)
    }
    
    // MARK: - Private Methods
    
    private func loadAsset() async throws {
        // Load tracks
        let tracks = try await asset.loadTracks(withMediaType: .video)
        
        guard let track = tracks.first else {
            throw VideoDecoderError.noVideoTrack
        }
        
        self.videoTrack = track
        
        // Load track properties
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let duration = try await asset.load(.duration)
        let nominalFrameRate = try await track.load(.nominalFrameRate)
        
        // Apply transform to get actual dimensions (handles rotation)
        let transformedSize = size.applying(transform)
        let width = abs(Int(transformedSize.width))
        let height = abs(Int(transformedSize.height))
        
        // Extract codec
        let formatDescriptions = try await track.load(.formatDescriptions)
        var codecString = "unknown"
        if let desc = formatDescriptions.first {
            let fourCC = CMFormatDescriptionGetMediaSubType(desc)
            codecString = fourCCToString(fourCC)
        }
        
        // Check for HDR
        var isHDR = false
        if let desc = formatDescriptions.first {
            if let colorPrimaries = CMFormatDescriptionGetExtension(
                desc,
                extensionKey: kCMFormatDescriptionExtension_ColorPrimaries
            ) as? String {
                isHDR = colorPrimaries == (kCMFormatDescriptionColorPrimaries_ITU_R_2020 as String)
            }
        }
        
        // Get estimated data rate
        let estimatedRate = try await track.load(.estimatedDataRate)
        
        self.metadata = VideoMetadata(
            resolution: SIMD2(width, height),
            frameRate: Double(nominalFrameRate),
            duration: duration,
            codec: codecString,
            hasAlpha: false,
            colorSpace: nil,
            isHDR: isHDR,
            estimatedDataRate: estimatedRate
        )
    }
    
    private func initializeReader(from startTime: CMTime) async throws {
        // Cancel existing reader
        assetReader?.cancelReading()
        
        guard let track = videoTrack else {
            throw VideoDecoderError.noVideoTrack
        }
        
        // Create reader
        do {
            assetReader = try AVAssetReader(asset: asset)
        } catch {
            throw VideoDecoderError.readerCreationFailed(error)
        }
        
        guard let reader = assetReader else {
            throw VideoDecoderError.readerCreationFailed(NSError(domain: "VideoDecoder", code: -1))
        }
        
        // Set time range if seeking
        if startTime > .zero {
            reader.timeRange = CMTimeRange(start: startTime, end: duration)
        }
        
        // Create track output with optimized settings
        // Include target resolution for efficient decode-time scaling
        var outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: config.outputPixelFormat,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
            // CRITICAL: Preserve source color space - don't let AVFoundation convert to sRGB/Display P3
            // This prevents automatic color space conversion that mangles colors
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ]
        ]
        
        // Add resolution scaling at decode time if target resolution specified
        // This is more efficient than scaling after decode
        if let targetRes = config.targetResolution {
            outputSettings[kCVPixelBufferWidthKey as String] = targetRes.x
            outputSettings[kCVPixelBufferHeightKey as String] = targetRes.y
        }
        
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false  // Zero-copy when possible
        
        guard reader.canAdd(output) else {
            throw VideoDecoderError.readerCreationFailed(NSError(domain: "VideoDecoder", code: -2))
        }
        
        reader.add(output)
        trackOutput = output
        
        guard reader.startReading() else {
            if let error = reader.error {
                throw VideoDecoderError.readerCreationFailed(error)
            }
            throw VideoDecoderError.readerCreationFailed(NSError(domain: "VideoDecoder", code: -3))
        }
    }
    
    private func createTextureCache() throws {
        var cache: CVMetalTextureCache?
        let status = CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            device,
            nil,
            &cache
        )
        
        guard status == kCVReturnSuccess, let createdCache = cache else {
            throw VideoDecoderError.textureCacheCreationFailed
        }
        
        self.textureCache = createdCache
    }
    
    private func textureFromCache(pixelBuffer: CVPixelBuffer, cache: CVMetalTextureCache) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        
        // Handle 10-bit YUV (HEVC HDR/10-bit)
        if pixelFormat == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange {
            return convertYUVToRGB(pixelBuffer, width: width, height: height)
        }
        
        // Handle 8-bit BGRA (Standard)
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )
        
        guard status == kCVReturnSuccess, let cvTex = cvTexture,
              let sourceTexture = CVMetalTextureGetTexture(cvTex) else {
            return nil
        }
        
        return copyTexture(sourceTexture)
    }

    private func convertYUVToRGB(_ pixelBuffer: CVPixelBuffer, width: Int, height: Int) -> MTLTexture? {
        guard let cache = textureCache else { return nil }
        
        // Create Y texture (Plane 0)
        var yTextureRef: CVMetalTexture?
        let yStatus = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            pixelBuffer,
            nil,
            .r16Unorm, 
            width,
            height,
            0,
            &yTextureRef
        )
        
        // Create UV texture (Plane 1)
        var uvTextureRef: CVMetalTexture?
        let uvStatus = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            pixelBuffer,
            nil,
            .rg16Unorm,
            width / 2,
            height / 2,
            1,
            &uvTextureRef
        )
        
        guard yStatus == kCVReturnSuccess, let yTex = yTextureRef, let yTexture = CVMetalTextureGetTexture(yTex),
              uvStatus == kCVReturnSuccess, let uvTex = uvTextureRef, let uvTexture = CVMetalTextureGetTexture(uvTex) else {
            return nil
        }
        
        // Create output texture (.rgba16Float)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        
        guard let outputTexture = device.makeTexture(descriptor: descriptor) else { return nil }
        
        // Dispatch conversion kernel
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return nil
        }
        
        // Load pipeline if needed
        if yuvConversionPipeline == nil {
            do {
                let library = try device.makeDefaultLibrary(bundle: Bundle.module)
                let function = library.makeFunction(name: "convert_yuv10_to_rgba16float")!
                yuvConversionPipeline = try device.makeComputePipelineState(function: function)
            } catch {
                print("❌ VideoDecoder: Failed to load YUV conversion pipeline: \(error)")
                return nil
            }
        }
        
        guard let pipeline = yuvConversionPipeline else { return nil }
        
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(yTexture, index: 0)
        encoder.setTexture(uvTexture, index: 1)
        encoder.setTexture(outputTexture, index: 2)
        
        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroups = MTLSize(
            width: (width + threadGroupSize.width - 1) / threadGroupSize.width,
            height: (height + threadGroupSize.height - 1) / threadGroupSize.height,
            depth: 1
        )
        
        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()
        commandBuffer.commit()
        
        return outputTexture
    }
    
    /// Creates an independent copy of a texture to prevent buffer reuse issues
    /// Uses async completion handler to avoid blocking the CPU
    private func copyTexture(_ source: MTLTexture) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: source.pixelFormat,
            width: source.width,
            height: source.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared  // Must be shared for CPU readback
        
        guard let destination = device.makeTexture(descriptor: descriptor) else {
            return nil
        }
        
        // Use blit encoder for GPU-side copy (much faster than CPU readback)
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            return nil
        }
        
        blitEncoder.copy(
            from: source,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: source.width, height: source.height, depth: 1),
            to: destination,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        
        blitEncoder.endEncoding()
        
        // OPTIMIZATION: Use synchronous wait only for immediate return
        // In async contexts, prefer completion handlers
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return destination
    }
    
    /// Async version of copyTexture using Swift concurrency
    /// Eliminates CPU stalls by awaiting GPU completion without blocking
    private func copyTextureAsync(_ source: MTLTexture) async -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: source.pixelFormat,
            width: source.width,
            height: source.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        
        guard let destination = device.makeTexture(descriptor: descriptor) else {
            return nil
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            return nil
        }
        
        blitEncoder.copy(
            from: source,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: source.width, height: source.height, depth: 1),
            to: destination,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        
        blitEncoder.endEncoding()
        commandBuffer.commit()
        
        // Await GPU completion without blocking CPU
        await commandBuffer.completed()
        
        return destination
    }
    
    private nonisolated func textureFromPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared  // Required for CPU readback in VideoExporter
        
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: baseAddress,
                bytesPerRow: bytesPerRow
            )
        }
        
        return texture
    }
    
    private nonisolated func fourCCToString(_ fourCC: FourCharCode) -> String {
        let chars: [Character] = [
            Character(UnicodeScalar((fourCC >> 24) & 0xFF)!),
            Character(UnicodeScalar((fourCC >> 16) & 0xFF)!),
            Character(UnicodeScalar((fourCC >> 8) & 0xFF)!),
            Character(UnicodeScalar(fourCC & 0xFF)!)
        ]
        return String(chars)
    }
}

// MARK: - VideoDecoder Statistics

extension VideoDecoder {
    /// Current position in seconds.
    public var currentTimeSeconds: Double {
        currentTime.seconds
    }
    
    /// Current frame number.
    public var currentFrame: Int {
        currentFrameNumber
    }
    
    /// Progress through the video (0.0-1.0).
    public var progress: Double {
        guard duration.seconds > 0 else { return 0 }
        return currentTime.seconds / duration.seconds
    }
    
    /// Whether the decoder has reached the end.
    public var isComplete: Bool {
        isAtEnd
    }
}
