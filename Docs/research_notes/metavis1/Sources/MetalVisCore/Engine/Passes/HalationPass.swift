import Metal
import simd

public class HalationPass: RenderPass {
    public var label: String = "Film Halation"
    public var inputs: [String] = ["main_buffer"]
    public var outputs: [String] = ["halation_composite"]
    
    private var thresholdPipeline: MTLComputePipelineState?
    private var blurHPipeline: MTLComputePipelineState?
    private var blurVPipeline: MTLComputePipelineState?
    private var accumulatePipeline: MTLComputePipelineState?
    private var compositePipeline: MTLComputePipelineState?
    private var halationDiskPipeline: MTLComputePipelineState?
    
    // Parameters
    public var threshold: Float = 0.8
    public var intensity: Float = 1.0
    public var radius: Float = 4.0
    public var tint: SIMD3<Float> = SIMD3<Float>(1.5, 0.5, 0.1) // Default Film Halation Tint
    public var radialFalloff: Bool = false  // V6.3: Distance-based falloff
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
        
        // If intensity is 0, just copy input to output (passthrough)
        if intensity <= 0.0 {
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
        desc.usage = [.shaderRead, .shaderWrite, .renderTarget] // Add .renderTarget for fast clear
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
        // Override halation radius with user parameter if needed, or use it as a multiplier?
        // The spec says "Use halationRadius to scale sampling distance."
        // But we also have a public var radius. Let's use the public var as the base.
        
        // 1. Threshold Pass
        guard let thresholdTexture = context.device.makeTexture(descriptor: desc) else { return }
        clearTexture(thresholdTexture)
        
        dispatch(encoder: commandBuffer.makeComputeCommandEncoder(),
                 pipeline: thresholdPipeline!,
                 inputs: [inputTexture],
                 output: thresholdTexture,
                 bytes: &threshold,
                 length: MemoryLayout<Float>.size)
        
        // 2. Blur (Exponential Disk)
        
        guard let accumTexture = context.device.makeTexture(descriptor: desc) else { return }
        clearTexture(accumTexture)
        
        if let diskPipeline = halationDiskPipeline {
            // Use High Quality Disk Blur
            let encoder = commandBuffer.makeComputeCommandEncoder()
            encoder?.setComputePipelineState(diskPipeline)
            encoder?.setTexture(thresholdTexture, index: 0)
            encoder?.setTexture(accumTexture, index: 1)
            encoder?.setBytes(&radius, length: MemoryLayout<Float>.size, index: 0)
            
            let w = diskPipeline.threadExecutionWidth
            let h = diskPipeline.maxTotalThreadsPerThreadgroup / w
            let threadsPerGroup = MTLSizeMake(w, h, 1)
            let threadsPerGrid = MTLSizeMake(accumTexture.width, accumTexture.height, 1)
            
            encoder?.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
            encoder?.endEncoding()
        } else {
             // Fallback
             guard let blit = commandBuffer.makeBlitCommandEncoder() else { return }
             blit.copy(from: thresholdTexture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: MTLSize(width: width, height: height, depth: 1), to: accumTexture, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
             blit.endEncoding()
        }
        
        // 4. Composite
        // NOTE: Metal struct layout: float (4 bytes) + float3 (16 bytes aligned) = 20 bytes total
        // BUT float3 forces 16-byte alignment, so struct is padded to 32 bytes
        // Swift SIMD3<Float> is 16 bytes (12 data + 4 padding), so we match Metal's layout
        struct HalationCompositeUniforms {
            var intensity: Float      // 4 bytes
            var time: Float           // 4 bytes (was _pad1)
            var radialFalloff: Int32  // 4 bytes (V6.3)
            var _pad3: Float = 0      // 4 bytes padding (total 16 for float4 alignment)
            var tint: SIMD3<Float>    // 12 bytes + 4 auto-pad = 16 bytes
            // Total: 32 bytes (matches Metal struct with float3 alignment)
        }
        
        var uniforms = HalationCompositeUniforms(
            intensity: intensity,
            time: Float(context.time),
            radialFalloff: radialFalloff ? 1 : 0,
            _pad3: 0,
            tint: tint
        )
        
        dispatch(encoder: commandBuffer.makeComputeCommandEncoder(),
                 pipeline: compositePipeline!,
                 inputs: [inputTexture, accumTexture],
                 output: outputTexture,
                 bytes: &uniforms,
                 length: MemoryLayout<HalationCompositeUniforms>.size)
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
        
        // Load Halation shaders (threshold, composite)
        // NOTE: This pass also requires blur kernels (fx_halation_blur_h/v) from Effects/Blur.metal
        // The blur kernels are loaded separately since they're reused across multiple effects
        if (try? library.makeFunction(name: "fx_halation_threshold")) == nil {
             try? library.loadSource(resource: "MetaVisFXShaders")
        }
        
        thresholdPipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "fx_halation_threshold"))
        blurHPipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "fx_blur_h"))
        blurVPipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "fx_blur_v"))
        accumulatePipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "fx_accumulate"))
        compositePipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "fx_halation_composite"))
        
        // Load new disk blur if available (it should be in the library now)
        if let diskFunction = try? library.makeFunction(name: "fx_halation_blur_disk") {
            halationDiskPipeline = try device.makeComputePipelineState(function: diskFunction)
        }
    }
}
