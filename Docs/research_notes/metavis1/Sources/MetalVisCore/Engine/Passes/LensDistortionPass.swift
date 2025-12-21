import Metal
import simd

public class LensDistortionPass: RenderPass {
    public var label: String = "Lens Distortion"
    public var inputs: [String] = ["main_buffer"]
    public var outputs: [String] = ["display_buffer"]
    
    private var pipelineState: MTLComputePipelineState?
    public var camera: PhysicalCamera
    
    // Parameters
    public var intensity: Float? = nil // If set, overrides camera.distortionK1
    
    public init(device: MTLDevice, camera: PhysicalCamera) {
        self.camera = camera
    }
    
    public func execute(context: RenderContext,
                        inputTextures: [String: MTLTexture],
                        outputTextures: [String: MTLTexture]) throws {
        
        if pipelineState == nil {
            do {
                try buildPipeline(device: context.device)
            } catch {
                print("LensDistortionPass: Failed to build pipeline: \(error)")
                return
            }
        }
        
        guard let pipeline = pipelineState,
              let inputTexture = inputTextures[inputs[0]],
              let outputTexture = outputTextures[outputs[0]] else {
            print("LensDistortionPass: Missing resources. Pipeline: \(pipelineState != nil), Input: \(inputTextures[inputs[0]] != nil), Output: \(outputTextures[outputs[0]] != nil)")
            return
        }
        
        guard let encoder = context.commandBuffer.makeComputeCommandEncoder() else {
            return
        }
        
        encoder.label = label
        encoder.setComputePipelineState(pipeline)
        
        encoder.setTexture(inputTexture, index: 0)
        encoder.setTexture(outputTexture, index: 1)
        
        struct BrownConradyParams {
            var k1: Float
            var k2: Float
            var p1: Float
            var p2: Float
        }
        
        var params = BrownConradyParams(
            k1: intensity ?? camera.distortionK1,
            k2: camera.distortionK2,
            p1: 0,
            p2: 0
        )
        
        encoder.setBytes(&params, length: MemoryLayout<BrownConradyParams>.stride, index: 0)
        
        let w = pipeline.threadExecutionWidth
        let h = pipeline.maxTotalThreadsPerThreadgroup / w
        let threadsPerGroup = MTLSizeMake(w, h, 1)
        let threadsPerGrid = MTLSizeMake(outputTexture.width, outputTexture.height, 1)
        
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
    }
    
    private func buildPipeline(device: MTLDevice) throws {
        let library = ShaderLibrary(device: device)
        
        if (try? library.makeFunction(name: "fx_lens_distortion_brown_conrady")) == nil {
             try? library.loadSource(resource: "MetaVisFXShaders")
        }
        
        let function = try library.makeFunction(name: "fx_lens_distortion_brown_conrady")
        
        self.pipelineState = try device.makeComputePipelineState(function: function)
    }
}
