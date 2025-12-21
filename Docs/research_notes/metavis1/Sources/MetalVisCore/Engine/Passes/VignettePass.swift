import Metal
import simd

public class VignettePass: RenderPass {
    public var label: String = "Physical Vignette"
    public var inputs: [String] = ["main_buffer"]
    public var outputs: [String] = ["display_buffer"]
    
    private var pipelineState: MTLComputePipelineState?
    
    // Parameters
    public var sensorWidth: Float = 36.0 // Full Frame
    public var focalLength: Float = 35.0
    public var intensity: Float = 1.0
    public var smoothness: Float = 0.75 // Default to Physical (Cos^4)
    public var roundness: Float = 1.0   // Default to Circular
    
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
        
        struct VignetteParams {
            var sensorWidth: Float
            var focalLength: Float
            var intensity: Float
            var smoothness: Float
            var roundness: Float
            var padding: Float = 0.0
        }
        
        var params = VignetteParams(
            sensorWidth: sensorWidth, 
            focalLength: focalLength, 
            intensity: intensity,
            smoothness: smoothness,
            roundness: roundness
        )
        encoder.setBytes(&params, length: MemoryLayout<VignetteParams>.stride, index: 0)
        
        let w = pipeline.threadExecutionWidth
        let h = pipeline.maxTotalThreadsPerThreadgroup / w
        let threadsPerGroup = MTLSizeMake(w, h, 1)
        let threadsPerGrid = MTLSizeMake(outputTexture.width, outputTexture.height, 1)
        
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
    }
    
    private func buildPipeline(device: MTLDevice) throws {
        let library = ShaderLibrary(device: device)
        
        if (try? library.makeFunction(name: "fx_vignette_physical")) == nil {
             try? library.loadSource(resource: "MetaVisFXShaders")
        }
        
        let function = try library.makeFunction(name: "fx_vignette_physical")
        self.pipelineState = try device.makeComputePipelineState(function: function)
    }
}
