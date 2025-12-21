import Metal
import simd

public class BloomPass: RenderPass {
    public var label: String = "Physically Based Bloom"
    public var inputs: [String] = ["main_buffer"]
    public var outputs: [String] = ["bloom_composite"]
    
    private var thresholdPipeline: MTLComputePipelineState?
    private var blurHPipeline: MTLComputePipelineState?
    private var blurVPipeline: MTLComputePipelineState?
    private var compositePipeline: MTLComputePipelineState?
    
    // Parameters
    public var threshold: Float = 1.0
    public var knee: Float = 0.5
    public var clampMax: Float = 65504.0 // FP16 max
    public var intensity: Float = 0.5
    public var preservation: Float = 0.95 // 0.0 = Additive, 1.0 = Energy Conserving
    public var radius: Float = 1.0 // Not used directly in fixed kernel, but could scale texture
    public var quality: MVQualityMode = .cinema
    
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
        
        // If intensity is 0, just copy input to output (passthrough)
        if intensity <= 0.0 {
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
        
        let commandBuffer = context.commandBuffer
        
        // We need intermediate textures for the bloom chain.
        // For a high-quality bloom, we usually downsample.
        // For this V1 implementation, we'll use full-res or half-res temp textures.
        // Let's request temporary textures from the pool manually or assume we have them.
        // Since RenderPipeline doesn't easily support internal temp textures yet, 
        // we will allocate them here (not ideal for perf, but functional) or use a TexturePool if accessible.
        // Ideally, we'd ask the context or pool.
        
        let width = inputTexture.width
        let height = inputTexture.height
        
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .private
        
        // Quality Settings
        var qualitySettings = MVQualitySettings(mode: quality)
        
        // 1. Threshold Pass (Prefilter)
        // Input: main_buffer -> Output: bloom_threshold
        guard let thresholdTexture = context.device.makeTexture(descriptor: desc) else { return }
        
        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.setComputePipelineState(thresholdPipeline!)
            encoder.setTexture(inputTexture, index: 0)
            encoder.setTexture(thresholdTexture, index: 1)
            encoder.setBytes(&threshold, length: MemoryLayout<Float>.size, index: 0)
            encoder.setBytes(&knee, length: MemoryLayout<Float>.size, index: 1)
            encoder.setBytes(&clampMax, length: MemoryLayout<Float>.size, index: 2)
            
            let w = thresholdPipeline!.threadExecutionWidth
            let h = thresholdPipeline!.maxTotalThreadsPerThreadgroup / w
            let threadsPerGroup = MTLSizeMake(w, h, 1)
            let threadsPerGrid = MTLSizeMake(width, height, 1)
            
            encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
            encoder.endEncoding()
        }
        
        // 2. Blur Horizontal
        // Input: bloom_threshold -> Output: bloom_blur_h
        guard let blurHTexture = context.device.makeTexture(descriptor: desc) else { return }
        
        let encoderH = commandBuffer.makeComputeCommandEncoder()
        encoderH?.setComputePipelineState(blurHPipeline!)
        encoderH?.setTexture(thresholdTexture, index: 0)
        encoderH?.setTexture(blurHTexture, index: 1)
        encoderH?.setBytes(&radius, length: MemoryLayout<Float>.size, index: 0)
        encoderH?.setBytes(&qualitySettings, length: MemoryLayout<MVQualitySettings>.size, index: 1)
        
        let w = blurHPipeline!.threadExecutionWidth
        let h = blurHPipeline!.maxTotalThreadsPerThreadgroup / w
        let threadsPerGroup = MTLSizeMake(w, h, 1)
        let threadsPerGrid = MTLSizeMake(width, height, 1)
        
        encoderH?.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        encoderH?.endEncoding()
        
        // 3. Blur Vertical
        // Input: bloom_blur_h -> Output: bloom_blur_v (Final Bloom)
        guard let blurVTexture = context.device.makeTexture(descriptor: desc) else { return }
        
        let encoderV = commandBuffer.makeComputeCommandEncoder()
        encoderV?.setComputePipelineState(blurVPipeline!)
        encoderV?.setTexture(blurHTexture, index: 0)
        encoderV?.setTexture(blurVTexture, index: 1)
        encoderV?.setBytes(&radius, length: MemoryLayout<Float>.size, index: 0)
        encoderV?.setBytes(&qualitySettings, length: MemoryLayout<MVQualitySettings>.size, index: 1)
        
        encoderV?.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        encoderV?.endEncoding()
        
        // 4. Composite
        // Input: main_buffer + bloom_blur_v -> Output: bloom_composite
        // Note: We write to a NEW output texture, we don't overwrite main_buffer unless requested.
        // The pipeline usually expects us to write to 'outputs[0]'.
        
        struct CompositeUniforms {
            var intensity: Float
            var preservation: Float
        }
        var uniforms = CompositeUniforms(intensity: intensity, preservation: preservation)
        
        dispatch(encoder: commandBuffer.makeComputeCommandEncoder(),
                 pipeline: compositePipeline!,
                 inputs: [inputTexture, blurVTexture],
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
        encoder.setTexture(output, index: inputs.count) // Output is next index
        
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
        
        // Ensure shaders are loaded
        if (try? library.makeFunction(name: "fx_bloom_prefilter")) == nil {
             try? library.loadSource(resource: "Effects/Bloom")
        }
        
        thresholdPipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "fx_bloom_prefilter"))
        blurHPipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "fx_blur_h"))
        blurVPipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "fx_blur_v"))
        compositePipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "fx_bloom_composite"))
    }
}
