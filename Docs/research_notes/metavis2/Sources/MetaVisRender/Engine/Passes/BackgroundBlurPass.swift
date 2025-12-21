//
//  BackgroundBlurPass.swift
//  MetaVisRender
//
//  Background blur effect using person segmentation
//

import Metal
import MetalKit

/// Pass that blurs background areas based on person segmentation
public class BackgroundBlurPass {
    
    // MARK: - Pipeline States
    
    private var horizontalBlurPipeline: MTLComputePipelineState?
    private var verticalBlurPipeline: MTLComputePipelineState?
    private var singlePassBlurPipeline: MTLComputePipelineState?
    
    // MARK: - Configuration
    
    /// Background blur settings
    public var settings: BackgroundBlurSettings = BackgroundBlurSettings()
    
    /// Input texture
    public var inputTexture: MTLTexture?
    
    /// Output texture (if nil, writes back to input)
    public var outputTexture: MTLTexture?
    
    /// Vision provider for person segmentation
    public var visionProvider: VisionProvider?
    
    /// Cached segmentation mask
    private var cachedSegmentationMask: MTLTexture?
    private var segmentationCacheTimestamp: Double = 0
    private let segmentationCacheDuration: Double = 0.5  // 500ms cache
    
    /// Use dual-pass separable blur (faster) vs single-pass (simpler)
    public var useSeparableBlur: Bool = true
    
    // MARK: - Initialization
    
    public init() {}
    
    public func setup(device: MTLDevice, library: MTLLibrary) throws {
        // Load blur kernel (we'll use the same function for both passes)
        if let fn = library.makeFunction(name: "fx_background_blur") {
            horizontalBlurPipeline = try device.makeComputePipelineState(function: fn)
            verticalBlurPipeline = try device.makeComputePipelineState(function: fn)
        }
        
        if let fn = library.makeFunction(name: "fx_background_blur_single") {
            singlePassBlurPipeline = try device.makeComputePipelineState(function: fn)
        }
    }
    
    // MARK: - Execute
    
    public func execute(commandBuffer: MTLCommandBuffer, context: RenderContext) throws {
        guard settings.enabled,
              let input = inputTexture,
              let visionProvider = visionProvider else { return }
        
        guard settings.radius > 0.1 else { return }
        
        let output = outputTexture ?? input
        
        // 1. Get person segmentation mask
        let segmentationMask = try getSegmentationMask(
            in: input,
            visionProvider: visionProvider,
            context: context
        )
        
        guard let segMask = segmentationMask else {
            // No segmentation available, just copy input to output
            if input !== output {
                if let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
                    blitEncoder.copy(from: input, to: output)
                    blitEncoder.endEncoding()
                }
            }
            return
        }
        
        // 2. Apply blur
        if useSeparableBlur {
            try applySeparableBlur(
                input: input,
                output: output,
                mask: segMask,
                context: context,
                commandBuffer: commandBuffer
            )
        } else {
            try applySinglePassBlur(
                input: input,
                output: output,
                mask: segMask,
                context: context,
                commandBuffer: commandBuffer
            )
        }
        
        // Return segmentation mask if not cached
        if segmentationMask !== cachedSegmentationMask {
            context.texturePool.return(segMask)
        }
    }
    
    // MARK: - Segmentation
    
    private func getSegmentationMask(
        in texture: MTLTexture,
        visionProvider: VisionProvider,
        context: RenderContext
    ) throws -> MTLTexture? {
        // Check cache
        let now = CACurrentMediaTime()
        if let cached = cachedSegmentationMask,
           (now - segmentationCacheTimestamp) < segmentationCacheDuration {
            return cached
        }
        
        // Get quality setting
        let quality: VisionProvider.SegmentationQuality
        switch settings.segmentationQuality.lowercased() {
        case "fast": quality = .fast
        case "accurate": quality = .accurate
        default: quality = .balanced
        }
        
        // Perform segmentation synchronously
        let semaphore = DispatchSemaphore(value: 0)
        var capturedMask: MTLTexture?
        
        Task {
            do {
                let result = try await visionProvider.segmentPeople(
                    in: texture,
                    quality: quality
                )
                capturedMask = result.texture
            } catch {
                // Segmentation failed
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        // Cache the result
        if let mask = capturedMask {
            cachedSegmentationMask = mask
            segmentationCacheTimestamp = now
        }
        
        return capturedMask
    }
    
    // MARK: - Blur Application
    
    private func applySeparableBlur(
        input: MTLTexture,
        output: MTLTexture,
        mask: MTLTexture,
        context: RenderContext,
        commandBuffer: MTLCommandBuffer
    ) throws {
        guard let horizontalPipeline = horizontalBlurPipeline,
              let verticalPipeline = verticalBlurPipeline else {
            return // Pipelines not available
        }
        
        // Get intermediate texture for horizontal pass
        guard let intermediate = context.texturePool.acquireIntermediate(
            pixelFormat: input.pixelFormat,
            width: input.width,
            height: input.height,
            usage: [.shaderRead, .shaderWrite]
        ) else {
            return // No intermediate texture available
        }
        
        var radius = settings.radius
        var threshold = settings.maskThreshold
        
        // Horizontal pass
        var isHorizontal: Int32 = 1
        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.setComputePipelineState(horizontalPipeline)
            encoder.setTexture(input, index: 0)
            encoder.setTexture(mask, index: 1)
            encoder.setTexture(intermediate, index: 2)
            encoder.setBytes(&radius, length: MemoryLayout<Float>.size, index: 0)
            encoder.setBytes(&threshold, length: MemoryLayout<Float>.size, index: 1)
            encoder.setBytes(&isHorizontal, length: MemoryLayout<Int32>.size, index: 2)
            
            dispatchThreads(encoder: encoder, pipeline: horizontalPipeline, width: input.width, height: input.height)
            encoder.endEncoding()
        }
        
        // Vertical pass
        isHorizontal = 0
        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.setComputePipelineState(verticalPipeline)
            encoder.setTexture(intermediate, index: 0)
            encoder.setTexture(mask, index: 1)
            encoder.setTexture(output, index: 2)
            encoder.setBytes(&radius, length: MemoryLayout<Float>.size, index: 0)
            encoder.setBytes(&threshold, length: MemoryLayout<Float>.size, index: 1)
            encoder.setBytes(&isHorizontal, length: MemoryLayout<Int32>.size, index: 2)
            
            dispatchThreads(encoder: encoder, pipeline: verticalPipeline, width: input.width, height: input.height)
            encoder.endEncoding()
        }
        
        context.texturePool.return(intermediate)
    }
    
    private func applySinglePassBlur(
        input: MTLTexture,
        output: MTLTexture,
        mask: MTLTexture,
        context: RenderContext,
        commandBuffer: MTLCommandBuffer
    ) throws {
        guard let pipeline = singlePassBlurPipeline else {
            return // Pipeline not available
        }
        
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return // Encoder creation failed
        }
        
        var radius = settings.radius
        var threshold = settings.maskThreshold
        
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(input, index: 0)
        encoder.setTexture(mask, index: 1)
        encoder.setTexture(output, index: 2)
        encoder.setBytes(&radius, length: MemoryLayout<Float>.size, index: 0)
        encoder.setBytes(&threshold, length: MemoryLayout<Float>.size, index: 1)
        
        dispatchThreads(encoder: encoder, pipeline: pipeline, width: input.width, height: input.height)
        encoder.endEncoding()
    }
    
    // MARK: - Helpers
    
    private func dispatchThreads(encoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState, width: Int, height: Int) {
        let threadgroupWidth = min(pipeline.threadExecutionWidth, width)
        let threadgroupHeight = min(pipeline.maxTotalThreadsPerThreadgroup / threadgroupWidth, height)
        let threadsPerThreadgroup = MTLSize(width: threadgroupWidth, height: threadgroupHeight, depth: 1)
        let threadgroupsPerGrid = MTLSize(
            width: (width + threadgroupWidth - 1) / threadgroupWidth,
            height: (height + threadgroupHeight - 1) / threadgroupHeight,
            depth: 1
        )
        encoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    }
    
    public func apply(
        _ texture: MTLTexture,
        commandBuffer: MTLCommandBuffer,
        context: RenderContext
    ) throws -> MTLTexture {
        inputTexture = texture
        outputTexture = nil
        try execute(commandBuffer: commandBuffer, context: context)
        return texture
    }
}
