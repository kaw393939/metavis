import AVFoundation
import CoreVideo
import CoreImage
import Metal
import Foundation
import VideoToolbox

// MARK: - VTCompressionSession Callback

/// C-callable compression callback for VTCompressionSession
/// This must be a global function (not closure) due to VideoToolbox requirements
private func compressionOutputCallback(
    _ outputCallbackRefCon: UnsafeMutableRawPointer?,
    _ sourceFrameRefCon: UnsafeMutableRawPointer?,
    _ status: OSStatus,
    _ infoFlags: VTEncodeInfoFlags,
    _ sampleBuffer: CMSampleBuffer?
) {
    guard status == noErr, let sampleBuffer = sampleBuffer else {
        print("❌ VTCompressionSession: Encoding error \(status)")
        return
    }
    
    // Extract encoder reference from refcon
    guard let refCon = outputCallbackRefCon else { return }
    let encoder = Unmanaged<VideoExporter>.fromOpaque(refCon).takeUnretainedValue()
    
    // Store encoded frame (actor-safe via nonisolated callback)
    encoder.storeEncodedFrame(sampleBuffer)
}

public enum VideoExporterError: Error {
    case outputURLAlreadyExists
    case cannotCreateAssetWriter(Error)
    case cannotAddInput
    case cannotStartWriting
    case cannotAppendFrame(Int)
    case cannotFinish
    case writingFailed(Error?)
    case codecNotSupported
    case gpuSubmissionFailed
}

/// Color depth options for video export
public enum ExportColorDepth: Sendable {
    case auto        // Auto-detect hardware, use best available
    case bit8        // Force 8-bit (with optional dithering)
    case bit10       // Force 10-bit (requires capable hardware)
}

/// Banding mitigation strategies
public enum BandingMitigation: Sendable {
    case none        // Raw quantization (fastest, visible banding in gradients)
    case dither      // Blue-noise dithering (eliminates banding, minimal cost)
    case auto        // Smart: dither for 8-bit, none for 10-bit
}

/// Video codec options for export
public enum ExportVideoCodec: String, Sendable {
    case h264 = "h264"
    case hevc = "hevc"
    case prores = "prores"
    
    var avCodecType: AVVideoCodecType {
        switch self {
        case .h264: return .h264
        case .hevc: return .hevc
        case .prores: return .proRes422HQ
        }
    }
    
    /// Whether this codec is supported on the current device
    var isSupported: Bool {
        switch self {
        case .h264: return true
        case .hevc: 
            // HEVC encoding requires macOS 10.13+ and compatible hardware
            if #available(macOS 10.13, *) {
                return AVAssetExportSession.allExportPresets().contains(AVAssetExportPresetHEVCHighestQuality)
            }
            return false
        case .prores: return true
        }
    }
}

/// Configuration for video export
public struct VideoExportConfig: Sendable {
    public let codec: ExportVideoCodec
    public let bitrate: Int?  // nil = auto-calculate
    public let quality: Double  // 0.0 - 1.0 for VBR modes
    public let keyframeInterval: Int?  // nil = auto (2 seconds)
    
    /// Color depth for export (auto, 8-bit, 10-bit)
    public let colorDepth: ExportColorDepth
    
    /// Banding mitigation strategy (none, dither, auto)
    public let bandingMitigation: BandingMitigation
    
    /// Enable async GPU submission with multiple in-flight frames
    public let enableAsyncGPU: Bool
    
    /// Number of frames that can be in-flight simultaneously (2-4 recommended)
    public let maxFramesInFlight: Int
    
    /// Use MTLSharedEvent for GPU-GPU synchronization (Apple Silicon optimization)
    public let useSharedEvent: Bool
    
    /// Bypass ACES color conversion (for validation/debugging)
    public let bypassColorConversion: Bool
    
    /// Dump raw float frames to disk (for HDR validation)
    public let dumpRawFrames: Bool
    
    public init(
        codec: ExportVideoCodec = .h264,
        bitrate: Int? = nil,
        quality: Double = 0.8,
        keyframeInterval: Int? = nil,
        colorDepth: ExportColorDepth = .auto,
        bandingMitigation: BandingMitigation = .auto,
        enableAsyncGPU: Bool = true,
        maxFramesInFlight: Int = 3,
        useSharedEvent: Bool = true,
        bypassColorConversion: Bool = false,
        dumpRawFrames: Bool = false
    ) {
        self.codec = codec
        self.bitrate = bitrate
        self.quality = min(1.0, max(0.0, quality))
        self.keyframeInterval = keyframeInterval
        self.colorDepth = colorDepth
        self.bandingMitigation = bandingMitigation
        self.enableAsyncGPU = enableAsyncGPU
        self.maxFramesInFlight = min(4, max(1, maxFramesInFlight))
        self.useSharedEvent = useSharedEvent
        self.bypassColorConversion = bypassColorConversion
        self.dumpRawFrames = dumpRawFrames
    }
    
    /// Default H.264 config - legacy compatibility (8-bit SDR)
    public static let h264 = VideoExportConfig(codec: .h264)
    
    /// HEVC config - 10-bit HDR for modern displays
    public static let hevc = VideoExportConfig(codec: .hevc, quality: 0.85)
    
    /// HEVC HDR config - optimized for YouTube HDR, Apple TV 4K, HDR displays
    /// Uses Media Engine for hardware-accelerated 10-bit encoding
    public static let hevcHDR = VideoExportConfig(
        codec: .hevc,
        quality: 0.90,
        colorDepth: .auto,
        bandingMitigation: .auto,
        enableAsyncGPU: true,
        maxFramesInFlight: 3,
        useSharedEvent: true
    )
    
    /// HEVC 8-bit with blue-noise dithering - eliminates banding, maximum compatibility
    /// Perfect for social media, streaming platforms, legacy devices
    public static let hevc8BitDithered = VideoExportConfig(
        codec: .hevc,
        quality: 0.85,
        colorDepth: .bit8,
        bandingMitigation: .dither
    )
    
    /// ProRes config - editing/mastering quality (10-bit)
    public static let prores = VideoExportConfig(codec: .prores)
    
    /// High-performance config with async GPU
    public static let highPerformance = VideoExportConfig(
        codec: .hevc,
        quality: 0.85,
        enableAsyncGPU: true,
        maxFramesInFlight: 3,
        useSharedEvent: true
    )
    
    /// Ultra-performance for multi-stream editing
    public static let ultraPerformance = VideoExportConfig(
        codec: .hevc,
        quality: 0.90,
        enableAsyncGPU: true,
        maxFramesInFlight: 4,
        useSharedEvent: true
    )
}

public actor VideoExporter {
    // AVAssetWriter path (8-bit fallback)
    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    
    // VTCompressionSession path (true 10-bit)
    private var compressionSession: VTCompressionSession?
    private var encodedFrames: [EncodedFrame] = []
    private var useVTCompression: Bool = false
    
    private var frameNumber: Int = 0
    private let width: Int
    private let height: Int
    private let frameRate: Int
    private let config: VideoExportConfig
    private let outputURL: URL
    
    private struct EncodedFrame {
        let sampleBuffer: CMSampleBuffer
        let presentationTime: CMTime
        let frameNumber: Int
    }
    
    /// Thread-safe encoded frame storage (called from compression callback)
    nonisolated func storeEncodedFrame(_ sampleBuffer: CMSampleBuffer) {
        // Store with actor-safe synchronization
        Task { [weak self] in
            await self?._storeEncodedFrame(sampleBuffer)
        }
    }
    
    private func _storeEncodedFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer) as CMTime? else {
            print("❌ VideoExporter: Could not get presentation time from sample buffer")
            return
        }
        
        let frame = EncodedFrame(
            sampleBuffer: sampleBuffer,
            presentationTime: presentationTime,
            frameNumber: encodedFrames.count
        )
        encodedFrames.append(frame)
    }
    
    /// Setup VTCompressionSession for true 10-bit encoding
    private func setupVTCompression() throws {
        var session: VTCompressionSession?
        
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(width),
            height: Int32(height),
            codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: [
                kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: kCFBooleanTrue
            ] as CFDictionary,
            imageBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferMetalCompatibilityKey as String: true
            ] as CFDictionary,
            compressedDataAllocator: nil,
            outputCallback: compressionOutputCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &session
        )
        
        guard status == noErr, let session = session else {
            print("❌ VideoExporter: VTCompressionSession creation failed: \(status)")
            throw VideoExporterError.cannotCreateAssetWriter(NSError(domain: "VideoToolbox", code: Int(status)))
        }
        
        self.compressionSession = session
        
        // Configure session
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_HEVC_Main10_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_Quality, value: config.quality as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: frameRate as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        
        // Color properties (BT.709 for SDR content)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ColorPrimaries, value: kCVImageBufferColorPrimaries_ITU_R_709_2 as CFString)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_TransferFunction, value: kCVImageBufferTransferFunction_ITU_R_709_2 as CFString)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_YCbCrMatrix, value: kCVImageBufferYCbCrMatrix_ITU_R_709_2 as CFString)
        
        // Prepare session
        VTCompressionSessionPrepareToEncodeFrames(session)
        
        print("✅ VideoExporter: VTCompressionSession ready (HEVC Main 10)")
    }
    
    /// Detect HEVC 10-bit encoding capabilities
    private static func detectHEVCCapabilities() -> (supports10Bit: Bool, supportsMain10Profile: Bool) {
        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: 1920, height: 1080,
            codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: nil,
            imageBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
            ] as CFDictionary,
            compressedDataAllocator: nil,
            outputCallback: nil, refcon: nil,
            compressionSessionOut: &session
            
        )
        
        let supports10Bit = (status == noErr)
        var supportsMain10 = false
        
        if let session = session {
            supportsMain10 = true
            VTCompressionSessionInvalidate(session)
        }
        
        return (supports10Bit, supportsMain10)
    }
    
    /// Generate 64x64 blue-noise texture for dithering
    private static func generateBlueNoiseTexture(device: MTLDevice) -> MTLTexture? {
        let size = 64
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: size,
            height: size,
            mipmapped: false
        )
        desc.usage = [.shaderRead]
        desc.storageMode = .shared
        
        guard let texture = device.makeTexture(descriptor: desc) else {
            return nil
        }
        
        // Generate blue-noise pattern using void-and-cluster algorithm
        // For simplicity, use a pre-computed pattern (Bayer-like but better)
        var pixels = [UInt8](repeating: 0, count: size * size)
        
        // Simple approximation: Combine multiple scales of hash patterns
        // Real blue-noise would use proper void-and-cluster or pre-computed data
        for y in 0..<size {
            for x in 0..<size {
                let idx = y * size + x
                // Multi-scale hash for better spectral properties than pure noise
                let h1 = ((x * 73856093) ^ (y * 19349663)) % 256
                let h2 = ((x * 83492791) ^ (y * 50331653)) % 256
                let h3 = ((x * 12582917) ^ (y * 41943041)) % 256
                pixels[idx] = UInt8((h1 + h2 + h3) / 3)
            }
        }
        
        texture.replace(
            region: MTLRegionMake2D(0, 0, size, size),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: size
        )
        
        return texture
    }
    
    /// Pixel buffer pool for efficient memory reuse
    private var pixelBufferPool: CVPixelBufferPool?
    
    /// Metal command queue for async GPU operations
    private var commandQueue: MTLCommandQueue?
    
    /// Metal device reference
    private var device: MTLDevice?
    
    /// Semaphore for limiting in-flight GPU frames (fallback)
    private let gpuFrameSemaphore: DispatchSemaphore
    
    /// MTLSharedEvent for GPU-GPU synchronization (Apple Silicon optimization)
    private var sharedEvent: MTLSharedEvent?
    private var sharedEventValue: UInt64 = 0
    
    /// Pending command buffers for async submission
    private var pendingCommandBuffers: [MTLCommandBuffer] = []
    
    /// Metal pipeline for RGBA16Float → BGRA8 conversion (legacy)
    private var conversionPipeline: MTLComputePipelineState?
    
    /// Metal pipeline for RGBA16Float → BGRA8 with dithering (Option C)
    private var ditheredConversionPipeline: MTLComputePipelineState?
    
    /// Metal pipeline for RGBA16Float → YUV10 conversion (HDR)
    private var yuvConversionPipeline: MTLComputePipelineState?
    
    /// Color space conversion pipeline (Linear RGB → Gamma-encoded RGB)
    private var colorSpaceConversionPipeline: MTLComputePipelineState?
    
    /// Intermediate texture for gamma-encoded RGB (before YUV conversion)
    private var gammaEncodedTexture: MTLTexture?
    
    /// Intermediate BGRA8 texture for conversion (legacy)
    private var conversionTexture: MTLTexture?
    
    /// Y plane texture for 10-bit YUV (full resolution)
    private var yPlaneTexture: MTLTexture?
    
    /// UV plane texture for 10-bit YUV (half resolution, 4:2:0)
    private var uvPlaneTexture: MTLTexture?
    
    /// Blue-noise texture for dithering (64x64, seamless tiling)
    private var blueNoiseTexture: MTLTexture?
    
    /// Dither strength buffer for shader
    private var ditherStrengthBuffer: MTLBuffer?
    
    /// Whether to use dithering for this export
    private let useDithering: Bool
    
    /// Whether to use 10-bit encoding
    private let use10Bit: Bool
    
    /// CVMetalTextureCache for zero-copy GPU→Media Engine (Option A)
    private var textureCache: CVMetalTextureCache?
    
    /// Whether to use zero-copy path (Apple Silicon optimization)
    private let useZeroCopy: Bool
    
    /// Pixel format being used for the video
    private let pixelFormat: OSType
    
    /// Creates a video exporter with default H.264 settings
    public init(outputURL: URL, width: Int, height: Int, frameRate: Int = 30) throws {
        try self.init(outputURL: outputURL, width: width, height: height, frameRate: frameRate, config: .h264)
    }
    
    /// Creates a video exporter with custom configuration
    public init(outputURL: URL, width: Int, height: Int, frameRate: Int = 30, config: VideoExportConfig) throws {
        self.outputURL = outputURL
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.config = config
        
        // Initialize semaphore for async GPU (must be done in init, not async)
        self.gpuFrameSemaphore = DispatchSemaphore(value: config.maxFramesInFlight)
        
        // Verify codec is supported
        guard config.codec.isSupported else {
            throw VideoExporterError.codecNotSupported
        }
        
        // Determine color depth based on config and hardware capabilities
        print("🔧 VideoExporter: colorDepth=\(config.colorDepth), bandingMitigation=\(config.bandingMitigation)")
        let hwCaps = Self.detectHEVCCapabilities()
        print("🔧 VideoExporter: Hardware supports 10-bit: \(hwCaps.supports10Bit)")
        
        // Determine if we use VTCompressionSession (true 10-bit) or AVAssetWriter (8-bit)
        let shouldUseVTCompression = config.colorDepth == .bit10 && hwCaps.supports10Bit && config.codec == .hevc
        
        // Enable zero-copy path for HEVC on Apple Silicon (Media Engine optimization)
        // Also enable for ProRes to support 10-bit P010 input
        let shouldUseZeroCopy = (config.codec == .hevc || config.codec == .prores) && hwCaps.supports10Bit
        self.useZeroCopy = shouldUseZeroCopy
        
        switch config.colorDepth {
        case .auto:
            self.use10Bit = hwCaps.supports10Bit && config.codec == .hevc && shouldUseZeroCopy
            self.useDithering = !self.use10Bit  // Dither only if 8-bit
            print("🔧 VideoExporter: Auto-detected \(self.use10Bit ? "10-bit" : "8-bit") support, dithering=\(self.useDithering), zero-copy=\(shouldUseZeroCopy)")
        case .bit8:
            self.use10Bit = false
            self.useDithering = config.bandingMitigation == .dither || config.bandingMitigation == .auto
            print("🔧 VideoExporter: Forced 8-bit mode, dithering=\(self.useDithering)")
        case .bit10:
            // Allow HEVC (if hardware supported) OR ProRes
            guard (hwCaps.supports10Bit && config.codec == .hevc) || config.codec == .prores else {
                throw VideoExporterError.codecNotSupported
            }
            self.use10Bit = true
            self.useDithering = false
            print("🔧 VideoExporter: Forced 10-bit mode, zero-copy=\(shouldUseZeroCopy)")
        }
        
        // Set VTCompression flag before pixel format determination
        self.useVTCompression = shouldUseVTCompression
        
        // Determine pixel format
        self.pixelFormat = self.use10Bit ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange : kCVPixelFormatType_32BGRA
        print("🔧 VideoExporter: Pixel format set to \(pixelFormat == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange ? "10-bit YUV (Video Range)" : "8-bit BGRA")")
        print("🔧 VideoExporter: Encoding path: \(self.useVTCompression ? "VTCompressionSession (true 10-bit)" : "AVAssetWriter")")
        
        let poolAttributes: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: config.maxFramesInFlight + 1
        ]
        
        // IOSurface properties for proper 10-bit support
        let ioSurfaceProps: [String: Any] = [
            kIOSurfaceWidth as String: width,
            kIOSurfaceHeight as String: height,
            kIOSurfacePixelFormat as String: pixelFormat,
            kIOSurfaceBytesPerElement as String: pixelFormat == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange ? 2 : 4
        ]
        
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferBytesPerRowAlignmentKey as String: 64,  // Metal alignment
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: ioSurfaceProps,
            // CRITICAL: Attach color space metadata to prevent automatic conversions
            kCVImageBufferColorPrimariesKey as String: kCVImageBufferColorPrimaries_ITU_R_709_2,
            kCVImageBufferTransferFunctionKey as String: kCVImageBufferTransferFunction_ITU_R_709_2,
            kCVImageBufferYCbCrMatrixKey as String: kCVImageBufferYCbCrMatrix_ITU_R_709_2
        ]
        
        var pool: CVPixelBufferPool?
        let poolStatus = CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            poolAttributes as CFDictionary,
            pixelBufferAttributes as CFDictionary,
            &pool
        )
        if poolStatus == kCVReturnSuccess {
            self.pixelBufferPool = pool
            print("✅ VideoExporter: CVPixelBufferPool created successfully")
            print("   Format: \(pixelFormat == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange ? "10-bit YUV 4:2:0" : "8-bit BGRA")")
        } else {
            print("⚠️ VideoExporter: CVPixelBufferPool creation failed with status \(poolStatus)")
        }
        
        // Create Metal command queue and shared event for async GPU operations
        if config.enableAsyncGPU, let device = MTLCreateSystemDefaultDevice() {
            self.device = device
            self.commandQueue = device.makeCommandQueue()
            
            // Create CVMetalTextureCache for zero-copy GPU→Media Engine (Apple Silicon)
            if self.useZeroCopy {
                var cache: CVMetalTextureCache?
                let status = CVMetalTextureCacheCreate(
                    kCFAllocatorDefault,
                    nil,
                    device,
                    nil,
                    &cache
                )
                if status == kCVReturnSuccess {
                    self.textureCache = cache
                    print("✅ VideoExporter: Created CVMetalTextureCache for zero-copy encoding")
                } else {
                    print("⚠️ VideoExporter: CVMetalTextureCache creation failed (\(status)), falling back to CPU copy")
                }
            }
            
            // Create MTLSharedEvent for efficient GPU-GPU synchronization
            // This is more efficient than DispatchSemaphore for GPU work
            if config.useSharedEvent {
                self.sharedEvent = device.makeSharedEvent()
                self.sharedEvent?.label = "VideoExporter Sync"
            }
            
            // Create conversion pipelines
            do {
                let compiler = ShaderCompiler(bundle: Bundle.module, rootDirectory: "Shaders")
                
                // Load color space conversion shader (Linear RGB → Gamma-encoded RGB)
                let colorSpaceSource = try compiler.compile(file: "Core/ColorSpaceConversion.metal")
                let colorSpaceLibrary = try device.makeLibrary(source: colorSpaceSource, options: nil)
                if let colorSpaceKernel = colorSpaceLibrary.makeFunction(name: "prepare_for_video_export") {
                    self.colorSpaceConversionPipeline = try device.makeComputePipelineState(function: colorSpaceKernel)
                    print("✅ VideoExporter: Created Linear RGB → BT.709 Gamma pipeline")
                    
                    // Create intermediate texture for gamma-encoded RGB (rgba16Float)
                    let gammaDesc = MTLTextureDescriptor.texture2DDescriptor(
                        pixelFormat: .rgba16Float,
                        width: width,
                        height: height,
                        mipmapped: false
                    )
                    gammaDesc.usage = [.shaderWrite, .shaderRead]
                    gammaDesc.storageMode = .private  // GPU-only, no CPU access needed
                    if let gammaTex = device.makeTexture(descriptor: gammaDesc) {
                        self.gammaEncodedTexture = gammaTex
                        print("✅ VideoExporter: Created gamma-encoded intermediate texture (\(width)x\(height), rgba16Float)")
                    } else {
                        print("⚠️ VideoExporter: Failed to create gamma-encoded texture")
                    }
                } else {
                    print("⚠️ VideoExporter: Color space conversion shader not found")
                }
                
                // Load YUV conversion shader
                let source = try compiler.compile(file: "Core/TextureConversion.metal")
                let library = try device.makeLibrary(source: source, options: nil)
                
                // 10-bit YUV pipeline for HEVC HDR or ProRes 10-bit
                if (config.codec == .hevc || config.codec == .prores), 
                   pixelFormat == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange {
                    
                    // Use zero-copy shader if CVMetalTextureCache available
                    let shaderName = self.textureCache != nil ? "convert_rgba16float_to_yuv10_zerocopy" : "convert_rgba16float_to_yuv10"
                    
                    if let yuvKernel = library.makeFunction(name: shaderName) {
                        self.yuvConversionPipeline = try device.makeComputePipelineState(function: yuvKernel)
                        print("✅ VideoExporter: Created RGBA16Float→YUV10 pipeline (\(shaderName))")
                        print("DEBUG: init set yuvPipeline=\(self.yuvConversionPipeline != nil)")
                    } else {
                        print("⚠️ VideoExporter: Shader \(shaderName) not found, trying fallback")
                        if let fallbackKernel = library.makeFunction(name: "convert_rgba16float_to_yuv10") {
                            self.yuvConversionPipeline = try device.makeComputePipelineState(function: fallbackKernel)
                            print("✅ VideoExporter: Created RGBA16Float→YUV10 pipeline (fallback)")
                        }
                    }
                    
                    // Create Y plane (full resolution, 10-bit)
                    let yDesc = MTLTextureDescriptor.texture2DDescriptor(
                        pixelFormat: .r16Unorm,
                        width: width,
                        height: height,
                        mipmapped: false
                    )
                    yDesc.usage = [.shaderWrite, .shaderRead]
                    yDesc.storageMode = .shared  // MUST be .shared for CPU access
                    if let yTex = device.makeTexture(descriptor: yDesc) {
                        self.yPlaneTexture = yTex
                        print("✅ VideoExporter: Created Y plane texture (\(width)x\(height), r16Unorm)")
                    } else {
                        print("⚠️ VideoExporter: Failed to create Y plane texture")
                    }
                    
                    // Create UV plane (half resolution, 10-bit, interleaved U+V)
                    let uvDesc = MTLTextureDescriptor.texture2DDescriptor(
                        pixelFormat: .rg16Unorm,  // Two channels for U+V
                        width: width / 2,
                        height: height / 2,
                        mipmapped: false
                    )
                    uvDesc.usage = [.shaderWrite, .shaderRead]
                    uvDesc.storageMode = .shared  // MUST be .shared for CPU access
                    if let uvTex = device.makeTexture(descriptor: uvDesc) {
                        self.uvPlaneTexture = uvTex
                        print("✅ VideoExporter: Created UV plane texture (\(width/2)x\(height/2), rg16Unorm)")
                    } else {
                        print("⚠️ VideoExporter: Failed to create UV plane texture")
                    }
                }
                
                // 8-bit BGRA pipelines (with and without dithering)
                if !self.use10Bit {
                    // Create conversion texture
                    let conversionDesc = MTLTextureDescriptor.texture2DDescriptor(
                        pixelFormat: .bgra8Unorm,
                        width: width,
                        height: height,
                        mipmapped: false
                    )
                    conversionDesc.usage = [.shaderWrite, .shaderRead]
                    conversionDesc.storageMode = .shared  // MUST be .shared for CPU access via getBytes()
                    self.conversionTexture = device.makeTexture(descriptor: conversionDesc)
                    
                    if self.useDithering {
                        // Create dithered pipeline (Option C)
                        if let ditheredKernel = library.makeFunction(name: "convert_rgba16float_to_bgra8_dithered") {
                            self.ditheredConversionPipeline = try device.makeComputePipelineState(function: ditheredKernel)
                            print("✅ VideoExporter: Created RGBA16Float→BGRA8 (dithered) pipeline")
                            
                            // Generate blue-noise texture
                            self.blueNoiseTexture = Self.generateBlueNoiseTexture(device: device)
                            if self.blueNoiseTexture != nil {
                                print("✅ VideoExporter: Generated 64x64 blue-noise texture")
                            }
                            
                            // Create dither strength buffer (1.0 = standard strength)
                            var ditherStrength: Float = 1.0
                            self.ditherStrengthBuffer = device.makeBuffer(
                                bytes: &ditherStrength,
                                length: MemoryLayout<Float>.size,
                                options: .storageModeShared
                            )
                        } else {
                            print("⚠️ VideoExporter: Dithered shader not found, falling back to non-dithered")
                        }
                    }
                    
                    // Always create non-dithered pipeline as fallback
                    if let bgra8Kernel = library.makeFunction(name: "convert_rgba16float_to_bgra8") {
                        self.conversionPipeline = try device.makeComputePipelineState(function: bgra8Kernel)
                        print("✅ VideoExporter: Created RGBA16Float→BGRA8 pipeline")
                    }
                }
            } catch {
                print("⚠️ VideoExporter: Failed to create conversion pipeline: \(error)")
                self.conversionPipeline = nil
                self.ditheredConversionPipeline = nil
                self.yuvConversionPipeline = nil
            }
        }
        
        // Remove existing file
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        
        // For 10-bit HEVC: use VTCompressionSession (bypasses AVAssetWriter's 8-bit conversion)
        // For 8-bit/H.264: use AVAssetWriter
        if useVTCompression {
            print("🎬 VideoExporter: Using VTCompressionSession for true 10-bit output")
            try setupVTCompression()
            // Don't create AVAssetWriter yet - we'll create it in passthrough mode during finish()
            return
        }
        
        print("🎬 VideoExporter: Using AVAssetWriter (8-bit path)")
        
        do {
            self.writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        } catch {
            throw VideoExporterError.cannotCreateAssetWriter(error)
        }
        
        // Build video settings based on config
        let videoSettings = buildVideoSettings()
        
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false
        self.writerInput = input
        
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(pixelFormat),
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
        )
        self.adaptor = adaptor
        
        guard let writer = self.writer else { throw VideoExporterError.cannotStartWriting }
        
        if writer.canAdd(input) {
            writer.add(input)
        } else {
            throw VideoExporterError.cannotAddInput
        }
        
        if !writer.startWriting() {
            throw VideoExporterError.cannotStartWriting
        }
        
        writer.startSession(atSourceTime: .zero)
    }
    
    /// Builds video settings dictionary based on configuration
    private nonisolated func buildVideoSettings() -> [String: Any] {
        // Calculate bitrate based on resolution and codec
        let pixelCount = width * height
        let referencePixels = 1920 * 1080
        
        // HEVC is ~40% more efficient than H.264
        let referenceBitrate: Int
        switch config.codec {
        case .h264:
            referenceBitrate = 15_000_000  // 15 Mbps for 1080p H.264
        case .hevc:
            referenceBitrate = 10_000_000  // 10 Mbps for 1080p HEVC (same quality, smaller file)
        case .prores:
            referenceBitrate = 220_000_000  // ~220 Mbps for ProRes 422 HQ
        }
        
        let bitrate = config.bitrate ?? (pixelCount * referenceBitrate) / referencePixels
        let keyframeInterval = config.keyframeInterval ?? (frameRate * 2)
        
        var compressionProperties: [String: Any] = [:]
        
        // Add codec-specific settings
        switch config.codec {
        case .h264:
            compressionProperties[AVVideoAverageBitRateKey] = bitrate
            compressionProperties[AVVideoExpectedSourceFrameRateKey] = frameRate
            compressionProperties[AVVideoMaxKeyFrameIntervalKey] = keyframeInterval
            compressionProperties[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
            compressionProperties[AVVideoAllowFrameReorderingKey] = true
        case .hevc:
            compressionProperties[AVVideoAverageBitRateKey] = bitrate
            compressionProperties[AVVideoExpectedSourceFrameRateKey] = frameRate
            compressionProperties[AVVideoMaxKeyFrameIntervalKey] = keyframeInterval
            // HEVC uses quality-based encoding
            compressionProperties[AVVideoQualityKey] = config.quality
            compressionProperties[AVVideoAllowFrameReorderingKey] = true
            
            // The encoder should auto-detect 10-bit from CVPixelBuffer format
            // Just ensure we're passing 10-bit buffers correctly
        case .prores:
            // ProRes is intra-frame only - doesn't use bitrate, keyframe intervals, or frame reordering
            // Only needs expected frame rate
            compressionProperties[AVVideoExpectedSourceFrameRateKey] = frameRate
        }
        
        var videoSettings: [String: Any] = [
            AVVideoCodecKey: config.codec.avCodecType,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compressionProperties
        ]
        
        // No HDR metadata - standard Rec.709 SDR output
        // AVAssetWriter will use default Rec.709 color space for BGRA→YUV conversion
        
        // For HEVC 10-bit, specify color properties at top level too
        if config.codec == .hevc {
            videoSettings[AVVideoColorPropertiesKey] = [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_2100_HLG,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020
            ]
        }
        
        return videoSettings
    }
    
    public func append(texture: MTLTexture) async throws {
        print("DEBUG: append called. yuvPipeline=\(yuvConversionPipeline != nil)")
        // VTCompressionSession path (no writer/adaptor needed)
        if let session = compressionSession, let cache = textureCache, let pipeline = yuvConversionPipeline {
            try await appendZeroCopy(
                texture: texture,
                textureCache: cache,
                yuvPipeline: pipeline
            )
            return
        }
        
        // AVAssetWriter path (requires writer/adaptor)
        guard let writerInput = self.writerInput, let adaptor = self.adaptor else { return }
        
        // Use zero-copy path if available (Apple Silicon Media Engine optimization)
        if useZeroCopy, let cache = textureCache, let pipeline = yuvConversionPipeline {
            try await appendZeroCopy(
                texture: texture,
                textureCache: cache,
                yuvPipeline: pipeline,
                writerInput: writerInput,
                adaptor: adaptor
            )
            return
        }
        
        // Use async GPU submission if enabled
        if config.enableAsyncGPU, let queue = commandQueue {
            try await appendAsync(texture: texture, commandQueue: queue, writerInput: writerInput, adaptor: adaptor)
        } else {
            try await appendSync(texture: texture, writerInput: writerInput, adaptor: adaptor)
        }
    }
    
    /// Zero-copy frame append (Option A: CVMetalTextureCache - Apple Silicon optimized)
    /// Writes directly to CVPixelBuffer-backed Metal textures, no CPU copies!
    private func appendZeroCopy(
        texture: MTLTexture,
        textureCache: CVMetalTextureCache,
        yuvPipeline: MTLComputePipelineState,
        writerInput: AVAssetWriterInput? = nil,
        adaptor: AVAssetWriterInputPixelBufferAdaptor? = nil
    ) async throws {

        
        // Wait for writer to be ready (AVAssetWriter path only)
        if let writerInput = writerInput {
            var waitCount = 0
            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000) // 1ms
                waitCount += 1
                if waitCount > 1000 {
                    throw VideoExporterError.cannotAppendFrame(frameNumber)
                }
            }
        }
        
        // Create CVPixelBuffer from pool
        guard let pool = pixelBufferPool else {
            throw VideoExporterError.cannotAppendFrame(frameNumber)
        }
        
        var cvPixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &cvPixelBuffer)
        guard status == kCVReturnSuccess, let pixelBuffer = cvPixelBuffer else {
            throw VideoExporterError.cannotAppendFrame(frameNumber)
        }
        
        // VALIDATION: Verify CVPixelBuffer is truly x420 (10-bit)
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        if pixelFormat != kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange {
            print("❌ VideoExporter: CVPixelBuffer format mismatch!")
            print("   Expected: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange (\(kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange))")
            print("   Got: \(pixelFormat)")
            throw VideoExporterError.cannotAppendFrame(frameNumber)
        }
        
        // VALIDATION: Check plane configuration
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        let yBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let uvBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        
        // For 16-bit storage: Y should be width * 2, UV should be width * 2 (interleaved U+V)
        let expectedYBytes = width * 2
        let expectedUVBytes = width * 2  // width/2 pixels * 2 components * 2 bytes
        
        if yBytesPerRow < expectedYBytes || uvBytesPerRow < expectedUVBytes {
            print("❌ VideoExporter: CVPixelBuffer stride mismatch (not 16-bit storage)!")
            print("   Y plane: expected ≥\(expectedYBytes), got \(yBytesPerRow)")
            print("   UV plane: expected ≥\(expectedUVBytes), got \(uvBytesPerRow)")
            throw VideoExporterError.cannotAppendFrame(frameNumber)
        }
        
        // Debug print on first frame
        if frameNumber == 0 {
            print("✅ CVPixelBuffer validation passed:")
            print("   Format: x420 (10-bit)")
            print("   Y stride: \(yBytesPerRow) bytes (\(width)x\(height))")
            print("   UV stride: \(uvBytesPerRow) bytes (\(width/2)x\(height/2))")
        }
        
        // Get Metal texture views of CVPixelBuffer planes (zero-copy!)
        var yMetalTexture: CVMetalTexture?
        var uvMetalTexture: CVMetalTexture?
        
        // Y plane (full resolution, r16Unorm for 10-bit)
        var yStatus = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .r16Unorm,
            width,
            height,
            0,  // Y plane index
            &yMetalTexture
        )
        
        // UV plane (half resolution, rg16Unorm for 10-bit)
        var uvStatus = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .rg16Unorm,
            width / 2,
            height / 2,
            1,  // UV plane index
            &uvMetalTexture
        )
        
        guard yStatus == kCVReturnSuccess, 
              uvStatus == kCVReturnSuccess,
              let yTex = yMetalTexture,
              let uvTex = uvMetalTexture,
              let yTexture = CVMetalTextureGetTexture(yTex),
              let uvTexture = CVMetalTextureGetTexture(uvTex),
              let device = device,
              let queue = commandQueue else {
            print("⚠️ VideoExporter: Zero-copy texture creation failed, falling back")
            throw VideoExporterError.cannotAppendFrame(frameNumber)
        }
        
        // Create command buffer for all operations
        guard let cmdBuffer = queue.makeCommandBuffer() else {
            throw VideoExporterError.gpuSubmissionFailed
        }
        
        // 1. Color Space Conversion (Linear ACEScg -> Rec.709 Gamma)
        // We must apply ACES RRT+ODT to convert to Rec.709 Gamma for export.
        // Unless bypassed for validation.
        
        let inputForYUV: MTLTexture
        
        if config.bypassColorConversion {
            if frameNumber == 0 {
                 print("ℹ️ VideoExporter: Bypassing ACES RRT+ODT (Validation Mode)")
            }
            // If bypassing, we assume the input texture is already in the target space (or we want raw output)
            // However, the YUV pipeline expects the 'gammaTexture' (rgba16Float).
            // We can just copy the input texture to the gammaTexture, or use the input texture directly if compatible.
            // But 'gammaTexture' is allocated as rgba16Float, same as input 'texture'.
            
            // We'll just use a blit to copy input to gammaTexture to keep the pipeline flow identical
            guard let blitEncoder = cmdBuffer.makeBlitCommandEncoder(),
                  let gammaTexture = gammaEncodedTexture else {
                throw VideoExporterError.gpuSubmissionFailed
            }
            
            blitEncoder.label = "Bypass Color Conversion (Copy)"
            blitEncoder.copy(from: texture, to: gammaTexture)
            blitEncoder.endEncoding()
            
            inputForYUV = gammaTexture
            
        } else {
            guard let colorPipeline = colorSpaceConversionPipeline,
                  let gammaTexture = gammaEncodedTexture,
                  let colorEncoder = cmdBuffer.makeComputeCommandEncoder() else {
                 throw VideoExporterError.gpuSubmissionFailed
            }
            
            colorEncoder.label = "Color Space Conversion (ACEScg -> Rec.709)"
            colorEncoder.setComputePipelineState(colorPipeline)
            colorEncoder.setTexture(texture, index: 0)
            colorEncoder.setTexture(gammaTexture, index: 1)
            
            let cw = colorPipeline.threadExecutionWidth
            let ch = colorPipeline.maxTotalThreadsPerThreadgroup / cw
            colorEncoder.dispatchThreads(
                MTLSizeMake(texture.width, texture.height, 1),
                threadsPerThreadgroup: MTLSizeMake(cw, ch, 1)
            )
            colorEncoder.endEncoding()
            
            if frameNumber == 0 {
                 print("ℹ️ VideoExporter: Applying ACES RRT+ODT (Linear ACEScg -> Rec.709 Gamma)")
            }
            
            inputForYUV = gammaTexture
        }
        
        // DUMP RAW FRAME (Validation Mode)
        if config.dumpRawFrames {
            dumpRawFrame(texture: inputForYUV, frameNumber: frameNumber)
        }
        
        // 2. YUV Conversion (Rec.709 Gamma -> YUV10)
        // Use the gamma-encoded texture as input for YUV conversion
        
        guard let encoder = cmdBuffer.makeComputeCommandEncoder() else {
            throw VideoExporterError.gpuSubmissionFailed
        }
        
        encoder.label = "Zero-Copy Gamma RGB → YUV10 (Media Engine)"
        encoder.setComputePipelineState(yuvPipeline)
        encoder.setTexture(inputForYUV, index: 0)  // Input: Gamma-encoded RGB (rgba16Float)
        encoder.setTexture(yTexture, index: 1)     // Output: Y plane (GPU-backed)
        encoder.setTexture(uvTexture, index: 2)    // Output: UV plane (GPU-backed)
        
        // Dispatch for 4:2:0 subsampling (process half-res for UV)
        let w = yuvPipeline.threadExecutionWidth
        let h = yuvPipeline.maxTotalThreadsPerThreadgroup / w
        let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
        let threadgroups = MTLSize(
            width: ((width / 2) + w - 1) / w,
            height: ((height / 2) + h - 1) / h,
            depth: 1
        )
        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
        
        cmdBuffer.commit()
        await cmdBuffer.completed()
        
        // Route to compression path based on configuration
        let time = CMTime(value: CMTimeValue(frameNumber), timescale: CMTimeScale(frameRate))
        
        if let session = compressionSession {
            // CRITICAL: Attach color space metadata to CVPixelBuffer
            // This tells VTCompressionSession how to interpret the YUV data
            CVBufferSetAttachment(
                pixelBuffer,
                kCVImageBufferColorPrimariesKey,
                kCVImageBufferColorPrimaries_ITU_R_709_2,
                .shouldPropagate
            )
            CVBufferSetAttachment(
                pixelBuffer,
                kCVImageBufferTransferFunctionKey,
                kCVImageBufferTransferFunction_ITU_R_709_2,
                .shouldPropagate
            )
            CVBufferSetAttachment(
                pixelBuffer,
                kCVImageBufferYCbCrMatrixKey,
                kCVImageBufferYCbCrMatrix_ITU_R_709_2,
                .shouldPropagate
            )
            
            // VTCompressionSession path (true 10-bit)
            let duration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
            let status = VTCompressionSessionEncodeFrame(
                session,
                imageBuffer: pixelBuffer,
                presentationTimeStamp: time,
                duration: duration,
                frameProperties: nil,
                sourceFrameRefcon: nil,
                infoFlagsOut: nil
            )
            
            guard status == noErr else {
                print("❌ VideoExporter: VTCompressionSession encoding failed: \(status)")
                throw VideoExporterError.cannotAppendFrame(frameNumber)
            }
        } else {
            // AVAssetWriter path (8-bit fallback)
            guard let adaptor = self.adaptor else {
                throw VideoExporterError.cannotAppendFrame(frameNumber)
            }
            
            guard adaptor.append(pixelBuffer, withPresentationTime: time) else {
                throw VideoExporterError.cannotAppendFrame(frameNumber)
            }
        }
        
        frameNumber += 1
    }
    
    /// Synchronous frame append (legacy CPU-copy path)
    private func appendSync(
        texture: MTLTexture,
        writerInput: AVAssetWriterInput,
        adaptor: AVAssetWriterInputPixelBufferAdaptor
    ) async throws {
        // Wait for ready with shorter interval
        var waitCount = 0
        while !writerInput.isReadyForMoreMediaData {
            try await Task.sleep(nanoseconds: 1_000_000) // 1ms
            waitCount += 1
            if waitCount > 1000 { // 1 second timeout
                throw VideoExporterError.cannotAppendFrame(frameNumber)
            }
        }
        
        // Convert texture to pixel buffer
        // CRITICAL: Input texture is .rgba16Float, output buffer is 8-bit or 10-bit
        // We MUST convert properly or we get garbage/black frames
        let pixelBuffer: CVPixelBuffer?
        
        if let device = device, let queue = commandQueue, texture.pixelFormat == .rgba16Float {
            
            // 1. Color Space Conversion (Linear ACEScg -> Rec.709 Gamma)
            var inputTexture = texture
            
            if config.bypassColorConversion {
                // Bypass mode: Just copy input to gammaTexture if needed, or use input directly
                // Since inputTexture is already set to texture, we just need to ensure it's in the right format for next steps.
                // If next steps expect gammaTexture (which is rgba16Float), and input is rgba16Float, we are good.
                // However, if we want to be safe and ensure 'inputTexture' points to 'gammaTexture' (which is owned by us), we can copy.
                
                if let gammaTexture = gammaEncodedTexture,
                   let cmdBuffer = queue.makeCommandBuffer(),
                   let blitEncoder = cmdBuffer.makeBlitCommandEncoder() {
                    
                    blitEncoder.label = "Bypass Color Conversion (Copy)"
                    blitEncoder.copy(from: texture, to: gammaTexture)
                    blitEncoder.endEncoding()
                    cmdBuffer.commit()
                    cmdBuffer.waitUntilCompleted()
                    
                    inputTexture = gammaTexture
                }
                
            } else if let colorPipeline = colorSpaceConversionPipeline,
               let gammaTexture = gammaEncodedTexture,
               let cmdBuffer = queue.makeCommandBuffer(),
               let colorEncoder = cmdBuffer.makeComputeCommandEncoder() {
                
                colorEncoder.label = "Color Space Conversion (ACEScg -> Rec.709)"
                colorEncoder.setComputePipelineState(colorPipeline)
                colorEncoder.setTexture(texture, index: 0)
                colorEncoder.setTexture(gammaTexture, index: 1)
                
                let w = colorPipeline.threadExecutionWidth
                let h = colorPipeline.maxTotalThreadsPerThreadgroup / w
                colorEncoder.dispatchThreads(
                    MTLSizeMake(texture.width, texture.height, 1),
                    threadsPerThreadgroup: MTLSizeMake(w, h, 1)
                )
                colorEncoder.endEncoding()
                cmdBuffer.commit()
                cmdBuffer.waitUntilCompleted()
                
                inputTexture = gammaTexture
            }

            // Check if we have YUV10 pipeline (for HEVC HDR)
            print("DEBUG: yuvPipeline=\(yuvConversionPipeline != nil), yTex=\(yPlaneTexture != nil), uvTex=\(uvPlaneTexture != nil), pixelFormat=\(pixelFormat), expected=\(kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange)")
            if let yuvPipeline = yuvConversionPipeline, 
               let yTex = yPlaneTexture, 
               let uvTex = uvPlaneTexture,
               pixelFormat == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange {
                // RGBA16Float → YUV10 conversion for HDR
                guard let cmdBuffer = queue.makeCommandBuffer(),
                      let encoder = cmdBuffer.makeComputeCommandEncoder() else {
                    throw VideoExporterError.gpuSubmissionFailed
                }
                
                encoder.label = "RGBA16Float → YUV10 HDR Conversion"
                encoder.setComputePipelineState(yuvPipeline)
                encoder.setTexture(inputTexture, index: 0)
                encoder.setTexture(yTex, index: 1)
                encoder.setTexture(uvTex, index: 2)
                
                let w = yuvPipeline.threadExecutionWidth
                let h = yuvPipeline.maxTotalThreadsPerThreadgroup / w
                let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
                let threadgroups = MTLSize(
                    width: (width + w - 1) / w,
                    height: (height + h - 1) / h,
                    depth: 1
                )
                encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
                encoder.endEncoding()
                cmdBuffer.commit()
                cmdBuffer.waitUntilCompleted()
                
                // Create 10-bit YUV CVPixelBuffer and copy Y/UV planes
                if let pool = pixelBufferPool {
                    var poolBuffer: CVPixelBuffer?
                    let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &poolBuffer)
                    if status == kCVReturnSuccess, let buffer = poolBuffer {
                        // Validate CVPixelBuffer format matches our expectation
                        let actualFormat = CVPixelBufferGetPixelFormatType(buffer)
                        guard actualFormat == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange else {
                            print("❌ CVPixelBuffer format mismatch!")
                            print("   Expected: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange (\(kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange))")
                            print("   Actual: \(actualFormat)")
                            print("   Falling back to 8-bit conversion")
                            pixelBuffer = nil
                            // Will fall through to 8-bit path below
                            return
                        }
                        
                        CVPixelBufferLockBaseAddress(buffer, [])
                        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
                        
                        // Copy Y plane (full resolution)
                        if let yAddress = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) {
                            let cvYBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
                            let metalYBytesPerRow = ((width * 2) + 63) & ~63  // r16Unorm = 2 bytes/pixel
                            let yRegion = MTLRegionMake2D(0, 0, width, height)
                            
                            // Use temp buffer with Metal stride
                            let tempY = UnsafeMutableRawPointer.allocate(byteCount: metalYBytesPerRow * height, alignment: 64)
                            defer { tempY.deallocate() }
                            yTex.getBytes(tempY, bytesPerRow: metalYBytesPerRow, from: yRegion, mipmapLevel: 0)
                            
                            // Copy to CVPixelBuffer
                            if cvYBytesPerRow == metalYBytesPerRow {
                                memcpy(yAddress, tempY, metalYBytesPerRow * height)
                            } else {
                                for y in 0..<height {
                                    let srcRow = tempY.advanced(by: y * metalYBytesPerRow)
                                    let dstRow = yAddress.advanced(by: y * cvYBytesPerRow)
                                    memcpy(dstRow, srcRow, width * 2)
                                }
                            }
                        }
                        
                        // Copy UV plane (half resolution, interleaved)
                        if let uvAddress = CVPixelBufferGetBaseAddressOfPlane(buffer, 1) {
                            let cvUVBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
                            let metalUVBytesPerRow = (((width / 2) * 4) + 63) & ~63  // rg16Unorm = 4 bytes/pixel
                            let uvRegion = MTLRegionMake2D(0, 0, width / 2, height / 2)
                            
                            // Use temp buffer with Metal stride
                            let tempUV = UnsafeMutableRawPointer.allocate(byteCount: metalUVBytesPerRow * (height / 2), alignment: 64)
                            defer { tempUV.deallocate() }
                            uvTex.getBytes(tempUV, bytesPerRow: metalUVBytesPerRow, from: uvRegion, mipmapLevel: 0)
                            
                            // CRITICAL FIX: CVPixelBuffer expects 10-bit packed format (2 bytes/sample)
                            // Metal rg16Unorm is 4 bytes/pixel, so we need to convert/pack
                            // For now, copy row-by-row with correct byte count
                            let bytesPerRow = min(cvUVBytesPerRow, width)  // 10-bit = ~2 bytes/sample for UV
                            for y in 0..<(height / 2) {
                                let srcRow = tempUV.advanced(by: y * metalUVBytesPerRow)
                                let dstRow = uvAddress.advanced(by: y * cvUVBytesPerRow)
                                memcpy(dstRow, srcRow, bytesPerRow)
                            }
                        }
                        
                        pixelBuffer = buffer
                    } else {
                        pixelBuffer = nil
                    }
                } else {
                    pixelBuffer = nil
                }
            } else if let conversionTex = conversionTexture {
                // RGBA16Float → BGRA8 conversion (with or without dithering)
                guard let cmdBuffer = queue.makeCommandBuffer(),
                      let encoder = cmdBuffer.makeComputeCommandEncoder() else {
                    throw VideoExporterError.gpuSubmissionFailed
                }
                
                // Choose pipeline based on dithering setting (Option C)
                let pipeline: MTLComputePipelineState
                if useDithering, 
                   let ditheredPipeline = ditheredConversionPipeline,
                   let blueNoise = blueNoiseTexture,
                   let ditherBuffer = ditherStrengthBuffer {
                    // Use dithered pipeline (Option C: eliminates banding)
                    encoder.label = "RGBA16Float → BGRA8 (Dithered)"
                    pipeline = ditheredPipeline
                    encoder.setTexture(inputTexture, index: 0)
                    encoder.setTexture(conversionTex, index: 1)
                    encoder.setTexture(blueNoise, index: 2)
                    encoder.setBuffer(ditherBuffer, offset: 0, index: 0)
                } else if let nonDitheredPipeline = conversionPipeline {
                    // Use non-dithered pipeline (fallback)
                    encoder.label = "RGBA16Float → BGRA8"
                    pipeline = nonDitheredPipeline
                    encoder.setTexture(inputTexture, index: 0)
                    encoder.setTexture(conversionTex, index: 1)
                } else {
                    encoder.endEncoding()
                    throw VideoExporterError.gpuSubmissionFailed
                }
                
                encoder.setComputePipelineState(pipeline)
                
                let w = pipeline.threadExecutionWidth
                let h = pipeline.maxTotalThreadsPerThreadgroup / w
                let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
                let threadgroups = MTLSize(
                    width: (width + w - 1) / w,
                    height: (height + h - 1) / h,
                    depth: 1
                )
                encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
                encoder.endEncoding()
                cmdBuffer.commit()
                cmdBuffer.waitUntilCompleted()
                
                // Convert BGRA8 texture to CVPixelBuffer
                if let pool = pixelBufferPool {
                    var poolBuffer: CVPixelBuffer?
                    let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &poolBuffer)
                    if status == kCVReturnSuccess, let buffer = poolBuffer {
                        CVPixelBufferLockBaseAddress(buffer, [])
                        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
                        
                        // Copy texture to CVPixelBuffer
                        if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
                            let cvBytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
                            let metalBytesPerRow = ((width * 4) + 63) & ~63  // 64-byte aligned (Metal requirement)
                            
                            let region = MTLRegionMake2D(0, 0, width, height)
                            
                            // Always use temp buffer with correct Metal stride to avoid AGX errors
                            let tempBuffer = UnsafeMutableRawPointer.allocate(byteCount: metalBytesPerRow * height, alignment: 64)
                            defer { tempBuffer.deallocate() }
                            
                            // Get bytes from texture using Metal's aligned stride
                            conversionTex.getBytes(tempBuffer, bytesPerRow: metalBytesPerRow, from: region, mipmapLevel: 0)
                            
                            // Copy to CVPixelBuffer (row by row if strides differ)
                            if cvBytesPerRow == metalBytesPerRow {
                                // Strides match - direct copy
                                memcpy(baseAddress, tempBuffer, metalBytesPerRow * height)
                            } else {
                                // Strides differ - row by row copy
                                for y in 0..<height {
                                    let srcRow = tempBuffer.advanced(by: y * metalBytesPerRow)
                                    let dstRow = baseAddress.advanced(by: y * cvBytesPerRow)
                                    memcpy(dstRow, srcRow, width * 4)
                                }
                            }
                        }
                        pixelBuffer = buffer
                    } else {
                        pixelBuffer = nil
                    }
                } else {
                    pixelBuffer = nil
                }
            } else {
                // No conversion pipeline available
                print("⚠️ VideoExporter: No conversion pipeline for RGBA16Float")
                pixelBuffer = nil
            }
        } else if texture.pixelFormat == .bgra8Unorm {
            // Direct copy for BGRA8
            if let pool = pixelBufferPool {
                var poolBuffer: CVPixelBuffer?
                let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &poolBuffer)
                if status == kCVReturnSuccess, let buffer = poolBuffer {
                    CVPixelBufferLockBaseAddress(buffer, [])
                    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
                    
                    if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
                        let cvBytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
                        let metalBytesPerRow = ((width * 4) + 63) & ~63  // Metal 64-byte alignment
                        let region = MTLRegionMake2D(0, 0, width, height)
                        
                        // Use temp buffer with Metal stride
                        let tempBuffer = UnsafeMutableRawPointer.allocate(byteCount: metalBytesPerRow * height, alignment: 64)
                        defer { tempBuffer.deallocate() }
                        texture.getBytes(tempBuffer, bytesPerRow: metalBytesPerRow, from: region, mipmapLevel: 0)
                        
                        // Copy to CVPixelBuffer
                        if cvBytesPerRow == metalBytesPerRow {
                            memcpy(baseAddress, tempBuffer, metalBytesPerRow * height)
                        } else {
                            for y in 0..<height {
                                let srcRow = tempBuffer.advanced(by: y * metalBytesPerRow)
                                let dstRow = baseAddress.advanced(by: y * cvBytesPerRow)
                                memcpy(dstRow, srcRow, width * 4)
                            }
                        }
                    }
                    pixelBuffer = buffer
                } else {
                    pixelBuffer = nil
                }
            } else {
                pixelBuffer = nil
            }
        } else {
            // Unsupported format
            print("⚠️ VideoExporter: Unsupported texture format \\(texture.pixelFormat)")
            pixelBuffer = nil
        }
        
        guard let buffer = pixelBuffer else {
            print("Failed to convert texture to pixel buffer")
            return
        }
        
        // Use precise timescale that evenly divides common frame rates
        // 90000 is divisible by 24, 25, 30, 60, etc.
        let timescale: CMTimeScale = 90000
        let frameValue = CMTimeValue(frameNumber) * CMTimeValue(timescale / Int32(frameRate))
        let presentationTime = CMTime(value: frameValue, timescale: timescale)
        
        if !adaptor.append(buffer, withPresentationTime: presentationTime) {
            throw VideoExporterError.cannotAppendFrame(frameNumber)
        }
        
        frameNumber += 1
    }
    
    /// Asynchronous frame append with GPU pipelining
    /// Uses MTLSharedEvent for optimal GPU-GPU synchronization on Apple Silicon
    private func appendAsync(
        texture: MTLTexture,
        commandQueue: MTLCommandQueue,
        writerInput: AVAssetWriterInput,
        adaptor: AVAssetWriterInputPixelBufferAdaptor
    ) async throws {
        // CRITICAL: appendAsync implementation currently does CPU copy via getBytes
        // which does not handle format conversion (rgba16Float -> bgra8).
        // Fallback to appendSync for rgba16Float textures to ensure correct conversion.
        if texture.pixelFormat == .rgba16Float {
             try await appendSync(texture: texture, writerInput: writerInput, adaptor: adaptor)
             return
        }

        // Use MTLSharedEvent if available (preferred for Apple Silicon)
        if let event = sharedEvent {
            try await appendWithSharedEvent(texture: texture, commandQueue: commandQueue, writerInput: writerInput, adaptor: adaptor, event: event)
        } else {
            // Fall back to semaphore-based synchronization
            try await appendWithSemaphore(texture: texture, commandQueue: commandQueue, writerInput: writerInput, adaptor: adaptor)
        }
    }
    
    /// Append using MTLSharedEvent for GPU synchronization (most efficient on Apple Silicon)
    private func appendWithSharedEvent(
        texture: MTLTexture,
        commandQueue: MTLCommandQueue,
        writerInput: AVAssetWriterInput,
        adaptor: AVAssetWriterInputPixelBufferAdaptor,
        event: MTLSharedEvent
    ) async throws {
        // Get pixel buffer from pool
        guard let pool = pixelBufferPool else {
            try await appendSync(texture: texture, writerInput: writerInput, adaptor: adaptor)
            return
        }
        
        var poolBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &poolBuffer)
        guard status == kCVReturnSuccess, let pixelBuffer = poolBuffer else {
            try await appendSync(texture: texture, writerInput: writerInput, adaptor: adaptor)
            return
        }
        
        // Calculate presentation time before async operations
        let timescale: CMTimeScale = 90000
        let frameValue = CMTimeValue(frameNumber) * CMTimeValue(timescale / Int32(frameRate))
        let presentationTime = CMTime(value: frameValue, timescale: timescale)
        let currentFrame = frameNumber
        
        frameNumber += 1
        sharedEventValue += 1
        _ = sharedEventValue  // eventValue reserved for GPU sync
        
        // Copy texture to pixel buffer
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        
        if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
            let cvBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            // Determine bytes per pixel from texture format
            let bytesPerPixel: Int
            switch texture.pixelFormat {
            case .bgra8Unorm, .rgba8Unorm:
                bytesPerPixel = 4
            case .rgba16Float:
                bytesPerPixel = 8
            default:
                bytesPerPixel = 4  // fallback
            }
            let metalBytesPerRow = ((width * bytesPerPixel) + 63) & ~63
            let region = MTLRegionMake2D(0, 0, width, height)
            
            // Use temp buffer with Metal stride
            let tempBuffer = UnsafeMutableRawPointer.allocate(byteCount: metalBytesPerRow * height, alignment: 64)
            defer { tempBuffer.deallocate() }
            texture.getBytes(tempBuffer, bytesPerRow: metalBytesPerRow, from: region, mipmapLevel: 0)
            
            // Copy to CVPixelBuffer
            if cvBytesPerRow == metalBytesPerRow {
                memcpy(baseAddress, tempBuffer, metalBytesPerRow * height)
            } else {
                for y in 0..<height {
                    let srcRow = tempBuffer.advanced(by: y * metalBytesPerRow)
                    let dstRow = baseAddress.advanced(by: y * cvBytesPerRow)
                    memcpy(dstRow, srcRow, width * bytesPerPixel)
                }
            }
        }
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        
        // Wait for writer to be ready
        var waitCount = 0
        while !writerInput.isReadyForMoreMediaData {
            try await Task.sleep(nanoseconds: 500_000) // 0.5ms for better responsiveness
            waitCount += 1
            if waitCount > 2000 {
                throw VideoExporterError.cannotAppendFrame(currentFrame)
            }
        }
        
        // Append the frame
        if !adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
            throw VideoExporterError.cannotAppendFrame(currentFrame)
        }
    }
    
    /// Append using DispatchSemaphore (fallback for non-Apple Silicon)
    private func appendWithSemaphore(
        texture: MTLTexture,
        commandQueue: MTLCommandQueue,
        writerInput: AVAssetWriterInput,
        adaptor: AVAssetWriterInputPixelBufferAdaptor
    ) async throws {
        // Wait for a slot in the GPU pipeline
        gpuFrameSemaphore.wait()
        
        // Get pixel buffer from pool
        guard let pool = pixelBufferPool else {
            gpuFrameSemaphore.signal()
            try await appendSync(texture: texture, writerInput: writerInput, adaptor: adaptor)
            return
        }
        
        var poolBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &poolBuffer)
        guard status == kCVReturnSuccess, let pixelBuffer = poolBuffer else {
            gpuFrameSemaphore.signal()
            try await appendSync(texture: texture, writerInput: writerInput, adaptor: adaptor)
            return
        }
        
        // Create command buffer for async blit
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            gpuFrameSemaphore.signal()
            throw VideoExporterError.gpuSubmissionFailed
        }
        
        // Calculate presentation time before async operations
        let timescale: CMTimeScale = 90000
        let frameValue = CMTimeValue(frameNumber) * CMTimeValue(timescale / Int32(frameRate))
        let presentationTime = CMTime(value: frameValue, timescale: timescale)
        let currentFrame = frameNumber
        
        frameNumber += 1
        
        // Copy texture to pixel buffer using GPU blit (if possible)
        // For now, use CPU path but signal completion via command buffer
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        
        if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
            let cvBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            // Determine bytes per pixel from texture format
            let bytesPerPixel: Int
            switch texture.pixelFormat {
            case .bgra8Unorm, .rgba8Unorm:
                bytesPerPixel = 4
            case .rgba16Float:
                bytesPerPixel = 8
            default:
                bytesPerPixel = 4  // fallback
            }
            let metalBytesPerRow = ((width * bytesPerPixel) + 63) & ~63
            let region = MTLRegionMake2D(0, 0, width, height)
            
            // Use temp buffer with Metal stride
            let tempBuffer = UnsafeMutableRawPointer.allocate(byteCount: metalBytesPerRow * height, alignment: 64)
            defer { tempBuffer.deallocate() }
            texture.getBytes(tempBuffer, bytesPerRow: metalBytesPerRow, from: region, mipmapLevel: 0)
            
            // Copy to CVPixelBuffer
            if cvBytesPerRow == metalBytesPerRow {
                memcpy(baseAddress, tempBuffer, metalBytesPerRow * height)
            } else {
                for y in 0..<height {
                    let srcRow = tempBuffer.advanced(by: y * metalBytesPerRow)
                    let dstRow = baseAddress.advanced(by: y * cvBytesPerRow)
                    memcpy(dstRow, srcRow, width * bytesPerPixel)
                }
            }
        }
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        
        // Add completion handler to signal semaphore and append frame
        commandBuffer.addCompletedHandler { [gpuFrameSemaphore] _ in
            // Signal semaphore to allow next frame
            gpuFrameSemaphore.signal()
        }
        
        commandBuffer.commit()
        
        // Wait for writer to be ready
        var waitCount = 0
        while !writerInput.isReadyForMoreMediaData {
            try await Task.sleep(nanoseconds: 1_000_000) // 1ms
            waitCount += 1
            if waitCount > 1000 {
                throw VideoExporterError.cannotAppendFrame(currentFrame)
            }
        }
        
        // Append the frame
        if !adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
            throw VideoExporterError.cannotAppendFrame(currentFrame)
        }
    }
    
    public func finish() async throws {
        // Handle VTCompressionSession path
        if let session = compressionSession {
            print("🎬 VideoExporter: Finalizing VTCompressionSession encoding...")
            print("   Expected frames: \(frameNumber)")
            
            // Complete compression
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            
            // Wait for all frames to be encoded (check every 100ms for up to 30 seconds)
            var waitCount = 0
            let maxWait = 300 // 30 seconds
            while encodedFrames.count < frameNumber && waitCount < maxWait {
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                waitCount += 1
                if waitCount % 10 == 0 {
                    print("   Waiting for encoding... \(encodedFrames.count)/\(frameNumber) frames")
                }
            }
            
            if encodedFrames.count < frameNumber {
                print("⚠️  VideoExporter: Timeout waiting for encoding, got \(encodedFrames.count)/\(frameNumber) frames")
            }
            
            print("📦 VideoExporter: Muxing \(encodedFrames.count) encoded frames...")
            
            // Sort frames by presentation time
            let sortedFrames = encodedFrames.sorted { $0.presentationTime < $1.presentationTime }
            
            // Create AVAssetWriter in passthrough mode (no re-encoding)
            let muxWriter: AVAssetWriter
            do {
                muxWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
            } catch {
                throw VideoExporterError.cannotCreateAssetWriter(error)
            }
            
            // Passthrough input - writes already-encoded HEVC
            let muxInput = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: nil // nil = passthrough mode
            )
            muxInput.expectsMediaDataInRealTime = false
            
            guard muxWriter.canAdd(muxInput) else {
                throw VideoExporterError.cannotAddInput
            }
            muxWriter.add(muxInput)
            
            guard muxWriter.startWriting() else {
                throw VideoExporterError.cannotFinish
            }
            muxWriter.startSession(atSourceTime: .zero)
            
            // Write encoded frames
            for frame in sortedFrames {
                while !muxInput.isReadyForMoreMediaData {
                    try await Task.sleep(nanoseconds: 1_000_000) // 1ms
                }
                
                guard muxInput.append(frame.sampleBuffer) else {
                    print("❌ VideoExporter: Failed to append frame \(frame.frameNumber)")
                    throw VideoExporterError.cannotFinish
                }
            }
            
            muxInput.markAsFinished()
            await muxWriter.finishWriting()
            
            if muxWriter.status == .failed {
                if let error = muxWriter.error {
                    print("❌ VideoExporter: Muxing failed: \(error.localizedDescription)")
                }
                throw VideoExporterError.cannotFinish
            }
            
            // Clean up
            VTCompressionSessionInvalidate(session)
            self.compressionSession = nil
            encodedFrames.removeAll()
            
            print("✅ VideoExporter: VTCompressionSession encoding complete")
            print("   Output: \(outputURL.path)")
            print("   Frames: \(sortedFrames.count)")
            return
        }
        
        // AVAssetWriter path
        guard let writer = self.writer, let writerInput = self.writerInput else { return }
        
        // Wait for all in-flight frames to complete
        if config.enableAsyncGPU {
            if sharedEvent == nil {
                // Using semaphore - drain it
                for _ in 0..<config.maxFramesInFlight {
                    gpuFrameSemaphore.wait()
                }
                for _ in 0..<config.maxFramesInFlight {
                    gpuFrameSemaphore.signal()
                }
            }
            // SharedEvent handles synchronization automatically
        }
        
        writerInput.markAsFinished()
        await writer.finishWriting()
        
        if writer.status == .failed {
            throw VideoExporterError.writingFailed(writer.error)
        }
    }
    
    /// Dump raw texture data to disk for validation
    private func dumpRawFrame(texture: MTLTexture, frameNumber: Int) {
        guard let device = device, let queue = commandQueue else { return }
        
        let bytesPerPixel = 8 // rgba16Float = 4 * 2 bytes
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = height * bytesPerRow
        
        // Create a buffer to read back data
        guard let readBuffer = device.makeBuffer(length: totalBytes, options: .storageModeShared) else {
            print("❌ VideoExporter: Failed to create read buffer for dump")
            return
        }
        
        guard let cmdBuffer = queue.makeCommandBuffer(),
              let blitEncoder = cmdBuffer.makeBlitCommandEncoder() else {
            return
        }
        
        blitEncoder.label = "Dump Raw Frame Blit"
        blitEncoder.copy(from: texture,
                         sourceSlice: 0,
                         sourceLevel: 0,
                         sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                         sourceSize: MTLSize(width: width, height: height, depth: 1),
                         to: readBuffer,
                         destinationOffset: 0,
                         destinationBytesPerRow: bytesPerRow,
                         destinationBytesPerImage: totalBytes)
        
        blitEncoder.endEncoding()
        cmdBuffer.commit()
        cmdBuffer.waitUntilCompleted()
        
        // Read data
        let data = Data(bytes: readBuffer.contents(), count: totalBytes)
        
        // Write to file
        // Use a sidecar directory "raw_frames" next to the output file
        let rawDir = outputURL.deletingPathExtension().appendingPathExtension("raw_frames")
        
        do {
            if !FileManager.default.fileExists(atPath: rawDir.path) {
                try FileManager.default.createDirectory(at: rawDir, withIntermediateDirectories: true, attributes: nil)
            }
            
            let filename = String(format: "frame_%05d.bin", frameNumber)
            let fileURL = rawDir.appendingPathComponent(filename)
            
            try data.write(to: fileURL)
            if frameNumber == 0 {
                print("✅ VideoExporter: Dumped raw frame 0 to \(fileURL.path)")
            }
        } catch {
            print("❌ VideoExporter: Failed to write raw frame: \(error)")
        }
    }
}
