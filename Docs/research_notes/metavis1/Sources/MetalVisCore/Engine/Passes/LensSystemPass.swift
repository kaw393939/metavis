import Metal
import simd

public class LensSystemPass: RenderPass {
    public var label: String = "Lens System (Distortion + CA)"
    public var inputs: [String] = ["main_buffer"]
    public var outputs: [String] = ["display_buffer"]
    
    private var pipelineState: MTLComputePipelineState?
    
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
        
        if pipelineState == nil {
            try buildPipeline(device: context.device)
        }
        
        guard let pipeline = pipelineState else { return }
        let commandBuffer = context.commandBuffer
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }
        
        encoder.label = label
        encoder.setComputePipelineState(pipeline)
        
        encoder.setTexture(inputTexture, index: 0)
        encoder.setTexture(outputTexture, index: 1)
        
        // Extract params from PhysicalCamera
        let camera = context.camera
        
        struct LensSystemParams {
            var k1: Float
            var k2: Float
            var chromaticAberration: Float
            var padding: Float
        }
        
        var params = LensSystemParams(
            k1: camera.distortionK1,
            k2: camera.distortionK2,
            chromaticAberration: camera.chromaticAberration,
            padding: 0
        )
        
        encoder.setBytes(&params, length: MemoryLayout<LensSystemParams>.size, index: 0)
        
        let w = pipeline.threadExecutionWidth
        let h = pipeline.maxTotalThreadsPerThreadgroup / w
        let threadsPerGroup = MTLSizeMake(w, h, 1)
        let threadsPerGrid = MTLSizeMake(outputTexture.width, outputTexture.height, 1)
        
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
    }
    
    private func buildPipeline(device: MTLDevice) throws {
        let library = ShaderLibrary(device: device)
        
        if (try? library.makeFunction(name: "fx_lens_system")) == nil {
             try? library.loadSource(resource: "Effects/Lens")
        }
        
        let function = try library.makeFunction(name: "fx_lens_system")
        self.pipelineState = try device.makeComputePipelineState(function: function)
    }
}
