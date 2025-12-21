// InputDeviceTransformPass.swift
// MetaVisRender
//
// Sprint 19: Color Management
// Converts input textures to Linear ACEScg working space

import Metal
import Foundation

/// A render pass that converts input textures from their source color space
/// to Linear ACEScg (AP1 primaries, linear transfer).
///
/// This pass is the "gatekeeper" of the color pipeline. All textures must
/// pass through this before any rendering operations.
///
/// ## Usage
/// ```swift
/// let idtPass = try InputDeviceTransformPass(device: device)
/// let acescgTexture = try idtPass.convert(
///     texture: sourceTexture,
///     from: .rec709,
///     commandBuffer: commandBuffer
/// )
/// ```
public class InputDeviceTransformPass {
    
    // MARK: - Properties
    
    private let device: MTLDevice
    private let idtPipeline: MTLComputePipelineState
    private let odtPipeline: MTLComputePipelineState
    
    /// Thread group size for compute dispatch
    private let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
    
    // MARK: - Initialization
    
    public init(device: MTLDevice) throws {
        self.device = device
        
        // Use ShaderLibrary which handles runtime compilation
        let library = try ShaderLibrary.loadDefaultLibrary(device: device)
        
        // Create IDT pipeline
        guard let idtFunction = library.makeFunction(name: "cs_idt_transform") else {
            throw ColorError.shaderFunctionNotFound("cs_idt_transform")
        }
        self.idtPipeline = try device.makeComputePipelineState(function: idtFunction)
        
        // Create ODT pipeline
        guard let odtFunction = library.makeFunction(name: "cs_odt_transform") else {
            throw ColorError.shaderFunctionNotFound("cs_odt_transform")
        }
        self.odtPipeline = try device.makeComputePipelineState(function: odtFunction)
    }
    
    // MARK: - IDT (Input Device Transform)
    
    /// Converts a texture from its source color space to Linear ACEScg.
    ///
    /// - Parameters:
    ///   - texture: The source texture to convert
    ///   - sourceSpace: The color space of the source texture
    ///   - commandBuffer: The command buffer to encode into
    /// - Returns: A new texture in Linear ACEScg color space
    public func convert(
        texture: MTLTexture,
        from sourceSpace: RenderColorSpace,
        commandBuffer: MTLCommandBuffer
    ) throws -> MTLTexture {
        // If already ACEScg linear, return as-is
        if sourceSpace == .acescg {
            return texture
        }
        
        // Create output texture
        let outputTexture = try createOutputTexture(matching: texture)
        
        // Encode the IDT compute pass
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw ColorError.encoderCreationFailed
        }
        
        encoder.label = "IDT: \(sourceSpace.name) → ACEScg"
        encoder.setComputePipelineState(idtPipeline)
        encoder.setTexture(texture, index: 0)
        encoder.setTexture(outputTexture, index: 1)
        
        // Set color space parameters
        var primaries = sourceSpace.primaries.idtShaderValue
        var transfer = sourceSpace.transfer.idtShaderValue
        encoder.setBytes(&primaries, length: MemoryLayout<UInt32>.size, index: 0)
        encoder.setBytes(&transfer, length: MemoryLayout<UInt32>.size, index: 1)
        
        // Dispatch
        let threadGroups = MTLSize(
            width: (texture.width + threadGroupSize.width - 1) / threadGroupSize.width,
            height: (texture.height + threadGroupSize.height - 1) / threadGroupSize.height,
            depth: 1
        )
        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()
        
        return outputTexture
    }
    
    /// Converts a texture in-place if possible, otherwise creates a new texture.
    ///
    /// This is more efficient when you don't need to preserve the original.
    public func convertInPlace(
        texture: MTLTexture,
        from sourceSpace: RenderColorSpace,
        commandBuffer: MTLCommandBuffer
    ) throws -> MTLTexture {
        // For now, always create a new texture (in-place requires read-write textures)
        return try convert(texture: texture, from: sourceSpace, commandBuffer: commandBuffer)
    }
    
    // MARK: - ODT (Output Device Transform)
    
    /// Converts a texture from Linear ACEScg to a display/output color space.
    ///
    /// - Parameters:
    ///   - texture: The source texture in Linear ACEScg
    ///   - destSpace: The target color space for output
    ///   - commandBuffer: The command buffer to encode into
    /// - Returns: A new texture in the destination color space
    public func convertToDisplay(
        texture: MTLTexture,
        to destSpace: RenderColorSpace,
        commandBuffer: MTLCommandBuffer
    ) throws -> MTLTexture {
        // If requesting ACEScg linear output, return as-is
        if destSpace == .acescg {
            return texture
        }
        
        // Create output texture
        let outputTexture = try createOutputTexture(matching: texture)
        
        // Encode the ODT compute pass
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw ColorError.encoderCreationFailed
        }
        
        encoder.label = "ODT: ACEScg → \(destSpace.name)"
        encoder.setComputePipelineState(odtPipeline)
        encoder.setTexture(texture, index: 0)
        encoder.setTexture(outputTexture, index: 1)
        
        // Set color space parameters
        var primaries = destSpace.primaries.idtShaderValue
        var transfer = destSpace.transfer.idtShaderValue
        encoder.setBytes(&primaries, length: MemoryLayout<UInt32>.size, index: 0)
        encoder.setBytes(&transfer, length: MemoryLayout<UInt32>.size, index: 1)
        
        // Dispatch
        let threadGroups = MTLSize(
            width: (texture.width + threadGroupSize.width - 1) / threadGroupSize.width,
            height: (texture.height + threadGroupSize.height - 1) / threadGroupSize.height,
            depth: 1
        )
        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()
        
        return outputTexture
    }
    
    // MARK: - Helpers
    
    private func createOutputTexture(matching source: MTLTexture) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: source.pixelFormat,
            width: source.width,
            height: source.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        
        // Use shared storage on Apple Silicon for CPU access if needed
        #if arch(arm64)
        descriptor.storageMode = .shared
        #else
        descriptor.storageMode = .managed
        #endif
        
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw ColorError.textureCreationFailed
        }
        
        return texture
    }
}

// MARK: - Errors

public enum ColorError: Error, LocalizedError {
    case shaderLibraryNotFound
    case shaderFunctionNotFound(String)
    case encoderCreationFailed
    case textureCreationFailed
    case invalidColorSpace
    
    public var errorDescription: String? {
        switch self {
        case .shaderLibraryNotFound:
            return "Metal shader library not found"
        case .shaderFunctionNotFound(let name):
            return "Shader function '\(name)' not found"
        case .encoderCreationFailed:
            return "Failed to create compute command encoder"
        case .textureCreationFailed:
            return "Failed to create output texture"
        case .invalidColorSpace:
            return "Invalid or unsupported color space"
        }
    }
}
