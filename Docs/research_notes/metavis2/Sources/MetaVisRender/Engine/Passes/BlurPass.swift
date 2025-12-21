//
//  BlurPass.swift
//  MetaVisRender
//
//  Standard Gaussian Blur Pass
//

import Metal
import simd

public class BlurPass: @unchecked Sendable {
    
    public let device: MTLDevice
    
    private let horizontalBlurPipeline: MTLComputePipelineState
    private let verticalBlurPipeline: MTLComputePipelineState
    
    private let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
    
    public init(device: MTLDevice) throws {
        self.device = device
        
        let library = try ShaderLibrary.loadDefaultLibrary(device: device)
        print("Available functions: \(library.functionNames)")
        
        // Try namespaced names first (since they are in Effects::Blur namespace)
        let hName = "fx_blur_h"
        let vName = "fx_blur_v"
        
        guard let hFunc = library.makeFunction(name: hName),
              let vFunc = library.makeFunction(name: vName) else {
            throw BlurPassError.shaderNotFound
        }
        
        self.horizontalBlurPipeline = try device.makeComputePipelineState(function: hFunc)
        self.verticalBlurPipeline = try device.makeComputePipelineState(function: vFunc)
    }
    
    public func blur(
        input: MTLTexture,
        radius: Float,
        commandBuffer: MTLCommandBuffer,
        texturePool: TexturePool
    ) -> MTLTexture? {
        if radius <= 0 { return input }
        
        // 1. Create Intermediate Texture (for H pass output)
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: input.pixelFormat,
            width: input.width,
            height: input.height,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite]
        
        guard let intermediate = texturePool.acquire(descriptor: desc) else { return nil }
        
        // 2. Create Output Texture (for V pass output)
        guard let output = texturePool.acquire(descriptor: desc) else { return nil }
        
        // 3. Horizontal Pass
        guard let hEncoder = commandBuffer.makeComputeCommandEncoder() else { return nil }
        hEncoder.label = "Blur Horizontal"
        hEncoder.setComputePipelineState(horizontalBlurPipeline)
        hEncoder.setTexture(input, index: 0)
        hEncoder.setTexture(intermediate, index: 1)
        
        var r = radius
        hEncoder.setBytes(&r, length: MemoryLayout<Float>.size, index: 0)
        
        // Quality settings (dummy for now, matching shader signature)
        var quality = MVQualitySettings(mode: .realtime)
        hEncoder.setBytes(&quality, length: MemoryLayout<MVQualitySettings>.stride, index: 1)
        
        let hGroups = MTLSize(
            width: (input.width + threadGroupSize.width - 1) / threadGroupSize.width,
            height: (input.height + threadGroupSize.height - 1) / threadGroupSize.height,
            depth: 1
        )
        hEncoder.dispatchThreadgroups(hGroups, threadsPerThreadgroup: threadGroupSize)
        hEncoder.endEncoding()
        
        // 4. Vertical Pass
        guard let vEncoder = commandBuffer.makeComputeCommandEncoder() else { return nil }
        vEncoder.label = "Blur Vertical"
        vEncoder.setComputePipelineState(verticalBlurPipeline)
        vEncoder.setTexture(intermediate, index: 0)
        vEncoder.setTexture(output, index: 1)
        
        vEncoder.setBytes(&r, length: MemoryLayout<Float>.size, index: 0)
        vEncoder.setBytes(&quality, length: MemoryLayout<MVQualitySettings>.stride, index: 1)
        
        let vGroups = MTLSize(
            width: (input.width + threadGroupSize.width - 1) / threadGroupSize.width,
            height: (input.height + threadGroupSize.height - 1) / threadGroupSize.height,
            depth: 1
        )
        vEncoder.dispatchThreadgroups(vGroups, threadsPerThreadgroup: threadGroupSize)
        vEncoder.endEncoding()
        
        return output
    }
}

public enum BlurPassError: Error {
    case shaderNotFound
}
