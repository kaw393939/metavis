import Metal
import simd

public class FilmGrainPass: RenderPass {
    public var label: String = "Film Grain"
    public var inputs: [String] = ["main_buffer"] // Usually runs after everything else
    public var outputs: [String] = ["display_buffer"]
    
    private var pipelineState: MTLComputePipelineState?
    
    // Parameters
    public var intensity: Float = 0.05
    public var time: Float = 0.0
    public var size: Float = 1.0          // V6.3: Grain scale
    public var shadowBoost: Float = 1.0  // V6.3: Shadow sensitivity
    
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
            guard let blitEncoder = context.commandBuffer.makeBlitCommandEncoder() else { return }
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
        
        if pipelineState == nil {
            try buildPipeline(device: context.device)
        }
        
        guard let pipeline = pipelineState else {
            return
        }
        
        guard let encoder = context.commandBuffer.makeComputeCommandEncoder() else { return }
        
        encoder.label = label
        encoder.setComputePipelineState(pipeline)
        
        encoder.setTexture(inputTexture, index: 0)
        encoder.setTexture(outputTexture, index: 1)
        
        struct FilmGrainUniforms {
            var time: Float
            var intensity: Float
            var size: Float        // V6.3
            var shadowBoost: Float // V6.3
        }
        
        // Use context time if not manually set?
        // Usually grain animates every frame.
        let effectiveTime = time > 0 ? time : Float(context.time)
        
        var uniforms = FilmGrainUniforms(
            time: effectiveTime,
            intensity: intensity,
            size: size,
            shadowBoost: shadowBoost
        )
        encoder.setBytes(&uniforms, length: MemoryLayout<FilmGrainUniforms>.stride, index: 0)
        
        let w = pipeline.threadExecutionWidth
        let h = pipeline.maxTotalThreadsPerThreadgroup / w
        let threadsPerGroup = MTLSizeMake(w, h, 1)
        let threadsPerGrid = MTLSizeMake(outputTexture.width, outputTexture.height, 1)
        
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
    }
    
    private func buildPipeline(device: MTLDevice) throws {
        let library = ShaderLibrary(device: device)
        
        if (try? library.makeFunction(name: "fx_film_grain")) == nil {
             try? library.loadSource(resource: "MetaVisFXShaders")
        }
        
        let function = try library.makeFunction(name: "fx_film_grain")
        self.pipelineState = try device.makeComputePipelineState(function: function)
    }
}
