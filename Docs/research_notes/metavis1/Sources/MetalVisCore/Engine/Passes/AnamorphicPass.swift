import Metal
import simd

public class AnamorphicPass: RenderPass {
    public var label: String = "Anamorphic Streaks"
    public var inputs: [String] = ["main_buffer"]
    public var outputs: [String] = ["anamorphic_composite"]
    
    private var thresholdPipeline: MTLComputePipelineState?
    private var blurHPipeline: MTLComputePipelineState?
    private var compositePipeline: MTLComputePipelineState?
    
    // Parameters
    public var threshold: Float = 0.85
    public var intensity: Float = 0.6
    public var streakLength: Float = 8.0 // Horizontal blur radius
    public var tint: SIMD3<Float> = SIMD3<Float>(0.0, 0.5, 1.0) // Cinematic Blue/Cyan
    public var quality: MVQualityMode = .cinema
    
    // Zero buffer for clearing
    private var zeroBuffer: MTLBuffer?
    private var zeroBufferSize: Int = 0
    
    public init(device: MTLDevice) {
        // No-op
    }
    
    public func execute(context: RenderContext,
                        inputTextures: [String: MTLTexture],
                        outputTextures: [String: MTLTexture]) throws {
        
        guard let inputTexture = inputTextures[inputs[0]],
              let outputTexture = outputTextures[outputs[0]] else {
            return
        }
        
        let commandBuffer = context.commandBuffer
        
        // Ensure zero buffer
        let requiredSize = inputTexture.width * inputTexture.height * 8
        if zeroBuffer == nil || zeroBufferSize < requiredSize {
            zeroBufferSize = requiredSize
            zeroBuffer = context.device.makeBuffer(length: requiredSize, options: .storageModeShared)
            if let ptr = zeroBuffer?.contents() {
                memset(ptr, 0, requiredSize)
            }
        }
        
        if intensity <= 0.0 {
            // Passthrough
            let commandBuffer = context.commandBuffer
            guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else { return }
            blitEncoder.copy(from: inputTexture,
                           sourceSlice: 0, sourceLevel: 0,
                           sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                           sourceSize: MTLSize(width: inputTexture.width, height: inputTexture.height, depth: 1),
                           to: outputTexture,
                           destinationSlice: 0, destinationLevel: 0,
                           destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            blitEncoder.endEncoding()
            return
        }
        
        if thresholdPipeline == nil {
            try buildPipelines(device: context.device)
        }
        
        let width = inputTexture.width
        let height = inputTexture.height
        
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
        desc.usage = [.shaderRead, .shaderWrite, .renderTarget]
        desc.storageMode = .private
        
        // Helper to clear texture
        func clearTexture(_ texture: MTLTexture) {
            guard let buffer = zeroBuffer, let blit = commandBuffer.makeBlitCommandEncoder() else { return }
            
            blit.copy(from: buffer,
                      sourceOffset: 0,
                      sourceBytesPerRow: texture.width * 8,
                      sourceBytesPerImage: texture.height * texture.width * 8,
                      sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1),
                      to: texture,
                      destinationSlice: 0,
                      destinationLevel: 0,
                      destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            blit.endEncoding()
        }
        
        // Quality Settings
        var qualitySettings = MVQualitySettings(mode: quality)
        
        // 1. Threshold Pass
        guard let thresholdTexture = context.device.makeTexture(descriptor: desc) else { return }
        clearTexture(thresholdTexture)
        
        dispatch(encoder: commandBuffer.makeComputeCommandEncoder(),
                 pipeline: thresholdPipeline!,
                 inputs: [inputTexture],
                 output: thresholdTexture,
                 bytes: &threshold,
                 length: MemoryLayout<Float>.size)
        
        // 2. Horizontal Blur (Multiple passes for longer streaks)
        var blurInput = thresholdTexture
        var blurOutput: MTLTexture?
        
        // Apply multiple horizontal blur passes for longer streaks
        // Use quality settings to determine pass count or radius
        // For anamorphic, we want very wide blurs.
        // We can use the streakLength as the base radius per pass.
        
        let blurPasses: Int
        switch quality {
        case .realtime: blurPasses = 1
        case .cinema: blurPasses = 2
        case .lab: blurPasses = 4
        }
        
        for _ in 0..<blurPasses {
            guard let tempTexture = context.device.makeTexture(descriptor: desc) else { return }
            clearTexture(tempTexture)
            
            var radius = streakLength
            
            let encoder = commandBuffer.makeComputeCommandEncoder()
            encoder?.setComputePipelineState(blurHPipeline!)
            encoder?.setTexture(blurInput, index: 0)
            encoder?.setTexture(tempTexture, index: 1)
            encoder?.setBytes(&radius, length: MemoryLayout<Float>.size, index: 0)
            encoder?.setBytes(&qualitySettings, length: MemoryLayout<MVQualitySettings>.size, index: 1)
            
            let w = blurHPipeline!.threadExecutionWidth
            let h = blurHPipeline!.maxTotalThreadsPerThreadgroup / w
            let threadsPerGroup = MTLSizeMake(w, h, 1)
            let threadsPerGrid = MTLSizeMake(tempTexture.width, tempTexture.height, 1)
            
            encoder?.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
            encoder?.endEncoding()
            
            blurInput = tempTexture
            blurOutput = tempTexture
        }
        
        guard let finalStreakTexture = blurOutput else { return }
        
        // 3. Composite
        struct CompositeUniforms {
            var intensity: Float
            var padding1: Float
            var padding2: Float
            var padding3: Float
            var tint: SIMD3<Float>
        }
        var uniforms = CompositeUniforms(intensity: intensity, padding1: 0, padding2: 0, padding3: 0, tint: tint)
        
        dispatch(encoder: commandBuffer.makeComputeCommandEncoder(),
                 pipeline: compositePipeline!,
                 inputs: [inputTexture, finalStreakTexture],
                 output: outputTexture,
                 bytes: &uniforms,
                 length: MemoryLayout<CompositeUniforms>.size)
    }
    
    private func dispatch(encoder: MTLComputeCommandEncoder?,
                          pipeline: MTLComputePipelineState,
                          inputs: [MTLTexture],
                          output: MTLTexture,
                          bytes: UnsafeRawPointer? = nil,
                          length: Int = 0) {
        guard let encoder = encoder else { return }
        encoder.setComputePipelineState(pipeline)
        
        for (i, texture) in inputs.enumerated() {
            encoder.setTexture(texture, index: i)
        }
        encoder.setTexture(output, index: inputs.count)
        
        if let bytes = bytes {
            encoder.setBytes(bytes, length: length, index: 0)
        }
        
        let w = pipeline.threadExecutionWidth
        let h = pipeline.maxTotalThreadsPerThreadgroup / w
        let threadsPerGroup = MTLSizeMake(w, h, 1)
        let threadsPerGrid = MTLSizeMake(output.width, output.height, 1)
        
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
    }
    
    private func buildPipelines(device: MTLDevice) throws {
        let library = ShaderLibrary(device: device)
        
        if (try? library.makeFunction(name: "fx_anamorphic_threshold")) == nil {
             try? library.loadSource(resource: "Effects/Anamorphic")
        }
        
        thresholdPipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "fx_anamorphic_threshold"))
        blurHPipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "fx_blur_h"))
        compositePipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "fx_anamorphic_composite"))
    }
}
