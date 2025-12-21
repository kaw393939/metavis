import Metal
import simd

public class ToneMapPass: RenderPass {
    public var label: String = "Tone Mapping (ACES)"
    public var inputs: [String] = ["main_buffer"]
    public var outputs: [String] = ["display_buffer"]
    
    public var exposure: Float = 0.0
    
    private var pipelineState: MTLComputePipelineState?
    
    public init(device: MTLDevice) {
        // No params for now
    }
    
    public func execute(context: RenderContext,
                        inputTextures: [String: MTLTexture],
                        outputTextures: [String: MTLTexture]) throws {
        
        if pipelineState == nil {
            try buildPipeline(device: context.device)
        }
        
        guard let pipeline = pipelineState,
              let inputTexture = inputTextures[inputs[0]],
              let outputTexture = outputTextures[outputs[0]] else {
            return
        }
        
        guard let encoder = context.commandBuffer.makeComputeCommandEncoder() else {
            return
        }
        
        encoder.label = label
        encoder.setComputePipelineState(pipeline)
        
        encoder.setTexture(inputTexture, index: 0)
        encoder.setTexture(outputTexture, index: 1)
        
        var exposureVal = self.exposure
        encoder.setBytes(&exposureVal, length: MemoryLayout<Float>.size, index: 0)
        
        let w = pipeline.threadExecutionWidth
        let h = pipeline.maxTotalThreadsPerThreadgroup / w
        let threadsPerGroup = MTLSizeMake(w, h, 1)
        let threadsPerGrid = MTLSizeMake(outputTexture.width, outputTexture.height, 1)
        
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
    }
    
    private func buildPipeline(device: MTLDevice) throws {
        let library = ShaderLibrary(device: device)
        
        if (try? library.makeFunction(name: "fx_tonemap_aces")) == nil {
             try? library.loadSource(resource: "Effects/ToneMapping")
        }
        
        let function = try library.makeFunction(name: "fx_tonemap_aces")
        
        self.pipelineState = try device.makeComputePipelineState(function: function)
    }
}
