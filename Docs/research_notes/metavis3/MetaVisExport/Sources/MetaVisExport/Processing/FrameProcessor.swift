// FrameProcessor.swift
// MetaVisRender
//
// Created for Sprint 13: Export & Delivery
// Frame processing for reframing, scaling, and color conversion

import Foundation
import Metal
import MetalPerformanceShaders
import CoreImage
import Accelerate

// MARK: - ScalingMode

/// How to scale content when aspect ratios differ
public enum ScalingMode: String, Codable, Sendable {
    /// Fill the target, cropping if needed
    case fill
    
    /// Fit within target, letterboxing if needed
    case fit
    
    /// Stretch to fill (may distort)
    case stretch
    
    /// Fill with specified crop region
    case crop
}

// MARK: - FrameProcessorError

public enum FrameProcessorError: Error, LocalizedError, Sendable {
    case deviceNotAvailable
    case textureCreationFailed
    case scalingFailed
    case colorConversionFailed
    case invalidRegion
    
    public var errorDescription: String? {
        switch self {
        case .deviceNotAvailable:
            return "Metal device not available"
        case .textureCreationFailed:
            return "Failed to create texture"
        case .scalingFailed:
            return "Failed to scale frame"
        case .colorConversionFailed:
            return "Failed to convert color space"
        case .invalidRegion:
            return "Invalid crop region"
        }
    }
}

// MARK: - CropRegion

/// Region to crop from source frame
public struct CropRegion: Sendable {
    /// Normalized X position (0-1)
    public let x: Double
    
    /// Normalized Y position (0-1)
    public let y: Double
    
    /// Normalized width (0-1)
    public let width: Double
    
    /// Normalized height (0-1)
    public let height: Double
    
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
    
    /// Full frame
    public static let full = CropRegion(x: 0, y: 0, width: 1, height: 1)
    
    /// Center region with specified aspect ratio
    public static func center(sourceAspect: Double, targetAspect: Double) -> CropRegion {
        if sourceAspect > targetAspect {
            // Source is wider, crop sides
            let width = targetAspect / sourceAspect
            let x = (1 - width) / 2
            return CropRegion(x: x, y: 0, width: width, height: 1)
        } else {
            // Source is taller, crop top/bottom
            let height = sourceAspect / targetAspect
            let y = (1 - height) / 2
            return CropRegion(x: 0, y: y, width: 1, height: height)
        }
    }
    
    /// Convert to pixel rect
    public func toPixelRect(width: Int, height: Int) -> (x: Int, y: Int, width: Int, height: Int) {
        let px = Int(Double(width) * x)
        let py = Int(Double(height) * y)
        let pw = Int(Double(width) * self.width)
        let ph = Int(Double(height) * self.height)
        return (px, py, pw, ph)
    }
    
    /// Check if valid
    public var isValid: Bool {
        x >= 0 && y >= 0 && width > 0 && height > 0 &&
        x + width <= 1 && y + height <= 1
    }
}

// MARK: - FrameProcessingConfig

/// Configuration for frame processing
public struct FrameProcessingConfig: Sendable {
    /// Source resolution
    public let sourceResolution: ExportResolution
    
    /// Target resolution
    public let targetResolution: ExportResolution
    
    /// Scaling mode
    public let scalingMode: ScalingMode
    
    /// Custom crop region (for .crop mode)
    public let cropRegion: CropRegion?
    
    /// Letterbox/pillarbox color
    public let backgroundColor: SIMD4<Float>
    
    /// Apply color correction
    public let colorCorrection: Bool
    
    public init(
        sourceResolution: ExportResolution,
        targetResolution: ExportResolution,
        scalingMode: ScalingMode = .fit,
        cropRegion: CropRegion? = nil,
        backgroundColor: SIMD4<Float> = SIMD4(0, 0, 0, 1),
        colorCorrection: Bool = false
    ) {
        self.sourceResolution = sourceResolution
        self.targetResolution = targetResolution
        self.scalingMode = scalingMode
        self.cropRegion = cropRegion
        self.backgroundColor = backgroundColor
        self.colorCorrection = colorCorrection
    }
    
    /// Compute effective crop region
    public var effectiveCropRegion: CropRegion {
        switch scalingMode {
        case .fill:
            return CropRegion.center(
                sourceAspect: sourceResolution.aspectRatio,
                targetAspect: targetResolution.aspectRatio
            )
        case .fit, .stretch:
            return .full
        case .crop:
            return cropRegion ?? .full
        }
    }
    
    /// Compute destination rect for fit mode
    public var fitRect: (x: Int, y: Int, width: Int, height: Int) {
        let sourceAspect = sourceResolution.aspectRatio
        let targetAspect = targetResolution.aspectRatio
        
        if sourceAspect > targetAspect {
            // Letterbox (black bars top/bottom)
            let height = Int(Double(targetResolution.width) / sourceAspect)
            let y = (targetResolution.height - height) / 2
            return (0, y, targetResolution.width, height)
        } else {
            // Pillarbox (black bars left/right)
            let width = Int(Double(targetResolution.height) * sourceAspect)
            let x = (targetResolution.width - width) / 2
            return (x, 0, width, targetResolution.height)
        }
    }
}

// MARK: - FrameProcessor

/// Processes video frames for export with reframing and scaling
///
/// Handles:
/// - Resolution changes (upscale/downscale)
/// - Aspect ratio conversion with letterbox/pillarbox/crop
/// - Center crop for fill mode
/// - Custom crop regions
/// - Color space conversion
public actor FrameProcessor {
    
    // MARK: - Properties
    
    /// Metal device
    private let device: MTLDevice
    
    /// Command queue
    private let commandQueue: MTLCommandQueue
    
    /// Image scaler
    private let scaler: MPSImageBilinearScale
    
    /// Core Image context for advanced processing
    private let ciContext: CIContext
    
    /// Processing configuration
    public let config: FrameProcessingConfig
    
    /// Output texture descriptor
    private let outputDescriptor: MTLTextureDescriptor
    
    /// Texture pool for output
    private var texturePool: [MTLTexture] = []
    
    // MARK: - Initialization
    
    public init(config: FrameProcessingConfig, device: MTLDevice? = nil) throws {
        guard let metalDevice = device ?? MTLCreateSystemDefaultDevice() else {
            throw FrameProcessorError.deviceNotAvailable
        }
        
        guard let queue = metalDevice.makeCommandQueue() else {
            throw FrameProcessorError.deviceNotAvailable
        }
        
        self.device = metalDevice
        self.commandQueue = queue
        self.config = config
        
        // Create scaler
        self.scaler = MPSImageBilinearScale(device: metalDevice)
        
        // Create CIContext
        self.ciContext = CIContext(mtlDevice: metalDevice, options: [
            .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
            .outputColorSpace: CGColorSpaceCreateDeviceRGB()
        ])
        
        // Create output texture descriptor
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,  // 16-bit float for HDR precision
            width: config.targetResolution.width,
            height: config.targetResolution.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        descriptor.storageMode = .private
        self.outputDescriptor = descriptor
    }
    
    // MARK: - Processing
    
    /// Process a frame
    public func process(_ sourceTexture: MTLTexture) async throws -> MTLTexture {
        // Get output texture
        let outputTexture = try getOutputTexture()
        
        // Clear output with background color
        try await clearTexture(outputTexture)
        
        // Determine processing mode
        switch config.scalingMode {
        case .stretch:
            // Direct scale to fill entire output
            try await scaleTexture(sourceTexture, to: outputTexture, destRegion: nil)
            
        case .fill:
            // Crop center and scale
            let cropRegion = config.effectiveCropRegion
            try await cropAndScale(sourceTexture, to: outputTexture, crop: cropRegion)
            
        case .fit:
            // Scale to fit with letterbox/pillarbox
            let destRect = config.fitRect
            try await scaleTexture(
                sourceTexture,
                to: outputTexture,
                destRegion: destRect
            )
            
        case .crop:
            // Use custom crop region
            guard let cropRegion = config.cropRegion, cropRegion.isValid else {
                throw FrameProcessorError.invalidRegion
            }
            try await cropAndScale(sourceTexture, to: outputTexture, crop: cropRegion)
        }
        
        return outputTexture
    }
    
    /// Process a frame with animated crop
    public func process(
        _ sourceTexture: MTLTexture,
        cropRegion: CropRegion
    ) async throws -> MTLTexture {
        let outputTexture = try getOutputTexture()
        try await clearTexture(outputTexture)
        try await cropAndScale(sourceTexture, to: outputTexture, crop: cropRegion)
        return outputTexture
    }
    
    // MARK: - Private Methods
    
    private func getOutputTexture() throws -> MTLTexture {
        // Reuse from pool if available
        if let texture = texturePool.popLast() {
            return texture
        }
        
        // Create new texture
        guard let texture = device.makeTexture(descriptor: outputDescriptor) else {
            throw FrameProcessorError.textureCreationFailed
        }
        
        return texture
    }
    
    /// Return texture to pool
    public func returnTexture(_ texture: MTLTexture) {
        if texturePool.count < 4 {  // Limit pool size
            texturePool.append(texture)
        }
    }
    
    private func clearTexture(_ texture: MTLTexture) async throws {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: Double(config.backgroundColor.x),
            green: Double(config.backgroundColor.y),
            blue: Double(config.backgroundColor.z),
            alpha: Double(config.backgroundColor.w)
        )
        
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }
        encoder.endEncoding()
        commandBuffer.commit()
        await commandBuffer.completed()
    }
    
    private func scaleTexture(
        _ source: MTLTexture,
        to destination: MTLTexture,
        destRegion: (x: Int, y: Int, width: Int, height: Int)?
    ) async throws {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw FrameProcessorError.scalingFailed
        }
        
        if let region = destRegion {
            // Scale to specific region
            // Create a temporary texture and then copy to region
            let tempDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: destination.pixelFormat,
                width: region.width,
                height: region.height,
                mipmapped: false
            )
            tempDescriptor.usage = [.shaderRead, .shaderWrite]
            
            guard let tempTexture = device.makeTexture(descriptor: tempDescriptor) else {
                throw FrameProcessorError.textureCreationFailed
            }
            
            // Scale to temp
            scaler.encode(
                commandBuffer: commandBuffer,
                sourceTexture: source,
                destinationTexture: tempTexture
            )
            
            // Blit to destination region
            if let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
                blitEncoder.copy(
                    from: tempTexture,
                    sourceSlice: 0,
                    sourceLevel: 0,
                    sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                    sourceSize: MTLSize(width: region.width, height: region.height, depth: 1),
                    to: destination,
                    destinationSlice: 0,
                    destinationLevel: 0,
                    destinationOrigin: MTLOrigin(x: region.x, y: region.y, z: 0)
                )
                blitEncoder.endEncoding()
            }
        } else {
            // Scale to full destination
            scaler.encode(
                commandBuffer: commandBuffer,
                sourceTexture: source,
                destinationTexture: destination
            )
        }
        
        commandBuffer.commit()
        await commandBuffer.completed()
    }
    
    private func cropAndScale(
        _ source: MTLTexture,
        to destination: MTLTexture,
        crop: CropRegion
    ) async throws {
        let pixelRect = crop.toPixelRect(width: source.width, height: source.height)
        
        // Create cropped texture
        let cropDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: source.pixelFormat,
            width: pixelRect.width,
            height: pixelRect.height,
            mipmapped: false
        )
        cropDescriptor.usage = [.shaderRead, .shaderWrite]
        
        guard let croppedTexture = device.makeTexture(descriptor: cropDescriptor),
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw FrameProcessorError.textureCreationFailed
        }
        
        // Copy cropped region
        if let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
            blitEncoder.copy(
                from: source,
                sourceSlice: 0,
                sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: pixelRect.x, y: pixelRect.y, z: 0),
                sourceSize: MTLSize(width: pixelRect.width, height: pixelRect.height, depth: 1),
                to: croppedTexture,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
            )
            blitEncoder.endEncoding()
        }
        
        // Scale cropped to destination
        scaler.encode(
            commandBuffer: commandBuffer,
            sourceTexture: croppedTexture,
            destinationTexture: destination
        )
        
        commandBuffer.commit()
        await commandBuffer.completed()
    }
}

// MARK: - Factory Methods

extension FrameProcessor {
    /// Create processor for aspect ratio change (landscape to portrait)
    public static func landscapeToPortrait(
        sourceWidth: Int,
        sourceHeight: Int,
        targetWidth: Int = 1080,
        targetHeight: Int = 1920
    ) throws -> FrameProcessor {
        try FrameProcessor(
            config: FrameProcessingConfig(
                sourceResolution: ExportResolution(width: sourceWidth, height: sourceHeight),
                targetResolution: ExportResolution(width: targetWidth, height: targetHeight),
                scalingMode: .fill
            )
        )
    }
    
    /// Create processor for letterboxing (portrait to landscape)
    public static func portraitToLandscape(
        sourceWidth: Int,
        sourceHeight: Int,
        targetWidth: Int = 1920,
        targetHeight: Int = 1080
    ) throws -> FrameProcessor {
        try FrameProcessor(
            config: FrameProcessingConfig(
                sourceResolution: ExportResolution(width: sourceWidth, height: sourceHeight),
                targetResolution: ExportResolution(width: targetWidth, height: targetHeight),
                scalingMode: .fit,
                backgroundColor: SIMD4(0, 0, 0, 1)
            )
        )
    }
    
    /// Create processor with preset
    public static func forPreset(
        _ preset: ExportPreset,
        sourceResolution: ExportResolution,
        scalingMode: ScalingMode = .fit
    ) throws -> FrameProcessor {
        try FrameProcessor(
            config: FrameProcessingConfig(
                sourceResolution: sourceResolution,
                targetResolution: preset.resolution,
                scalingMode: scalingMode
            )
        )
    }
}
