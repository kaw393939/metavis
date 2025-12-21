import Metal
import simd

public class ShimmerPass: RenderPass {
    public var label: String = "Light Shimmer"
    public var inputs: [String] = ["main_buffer"]
    public var outputs: [String] = ["shimmer_buffer"] // Usually writes back to main or a composite
    
    private var pipelineState: MTLComputePipelineState?
    
    // Parameters
    public var intensity: Float = 0.5
    public var speed: Float = 1.0
    public var width: Float = 0.1
    public var angle: Float = 45.0 // Not used in current kernel, but in spec
    
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
        
        if pipelineState == nil {
            try buildPipeline(device: context.device)
        }
        
        guard let pipeline = pipelineState,
              let encoder = context.commandBuffer.makeComputeCommandEncoder() else {
            return
        }
        
        encoder.label = label
        encoder.setComputePipelineState(pipeline)
        
        encoder.setTexture(inputTexture, index: 0)
        encoder.setTexture(outputTexture, index: 1)
        
        // Calculate time based on speed
        var timeVal = Float(context.time) * speed
        // Loop time to keep it in reasonable range if needed, or just let it run
        
        encoder.setBytes(&timeVal, length: MemoryLayout<Float>.size, index: 0)
        encoder.setBytes(&intensity, length: MemoryLayout<Float>.size, index: 1)
        encoder.setBytes(&width, length: MemoryLayout<Float>.size, index: 2)
        encoder.setBytes(&angle, length: MemoryLayout<Float>.size, index: 3)
        
        let w = pipeline.threadExecutionWidth
        let h = pipeline.maxTotalThreadsPerThreadgroup / w
        let threadsPerGroup = MTLSizeMake(w, h, 1)
        let threadsPerGrid = MTLSizeMake(outputTexture.width, outputTexture.height, 1)
        
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
    }
    
    private func buildPipeline(device: MTLDevice) throws {
        let library = ShaderLibrary(device: device)
        
        if (try? library.makeFunction(name: "add_shimmer")) == nil {
             try? library.loadSource(resource: "LightEffects")
        }
        
        let function = try library.makeFunction(name: "add_shimmer")
        self.pipelineState = try device.makeComputePipelineState(function: function)
    }
}
