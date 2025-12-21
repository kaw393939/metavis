import Metal
import simd

public class VolumetricPass: RenderPass {
    public var label: String = "Volumetric Lighting"
    public var inputs: [String] = ["main_buffer", "depth_buffer"]
    public var outputs: [String] = ["volumetric_buffer"]
    
    private var pipelineState: MTLComputePipelineState?
    private var blurHPipeline: MTLComputePipelineState?
    private var blurVPipeline: MTLComputePipelineState?
    private let scene: Scene
    
    public var quality: MVQualityMode = .cinema
    
    // Parameters
    public var decay: Float = 0.95
    public var weight: Float = 0.01
    public var exposure: Float = 1.0
    public var color: SIMD3<Float> = SIMD3<Float>(1, 1, 1)
    
    public init(device: MTLDevice, scene: Scene) {
        self.scene = scene
    }
    
    public func execute(context: RenderContext,
                        inputTextures: [String: MTLTexture],
                        outputTextures: [String: MTLTexture]) throws {
        
        if pipelineState == nil {
            try buildPipeline(device: context.device)
        }
        
        guard let pipeline = pipelineState,
              let inputTexture = inputTextures[inputs[0]],
              let depthTexture = inputTextures[inputs[1]],
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
        encoder.setTexture(depthTexture, index: 2)
        
        // Calculate Light Position in Screen Space
        // We use the first volumetric light found
        var lightPosUV = SIMD2<Float>(0.5, 0.5)
        var lightDepth: Float = 1.0 // Default to far plane
        
        if let light = scene.volumetricLights.first {
            let aspectRatio = Float(outputTexture.width) / Float(outputTexture.height)
            let uniforms = scene.camera.getUniforms(aspectRatio: aspectRatio)
            let viewProj = uniforms.viewProjectionMatrix
            
            let lightPosWorld = SIMD4<Float>(light.position, 1.0)
            var clipPos = viewProj * lightPosWorld
            
            // Perspective divide
            if clipPos.w != 0 {
                clipPos /= clipPos.w
            }
            
            // NDC (-1..1) to UV (0..1)
            lightPosUV.x = clipPos.x * 0.5 + 0.5
            lightPosUV.y = (1.0 - clipPos.y) * 0.5 // Flip Y for texture coords
            lightDepth = clipPos.z // NDC Depth
        }
        
        // Get Quality Settings
        let qualitySettings = MVQualitySettings(mode: quality)
        
        struct VolumetricParams {
            var lightPosition: SIMD2<Float>
            var density: Float
            var decay: Float
            var weight: Float
            var exposure: Float
            var samples: Int32
            var lightDepth: Float
            var color: SIMD3<Float>
        }
        
        var params = VolumetricParams(
            lightPosition: lightPosUV,
            density: scene.volumetricDensity,
            decay: decay,
            weight: weight,
            exposure: exposure,
            samples: Int32(qualitySettings.volumetricSteps),
            lightDepth: lightDepth,
            color: color
        )
        
        encoder.setBytes(&params, length: MemoryLayout<VolumetricParams>.stride, index: 0)
        
        let w = pipeline.threadExecutionWidth
        let h = pipeline.maxTotalThreadsPerThreadgroup / w
        let threadsPerGroup = MTLSizeMake(w, h, 1)
        let threadsPerGrid = MTLSizeMake(outputTexture.width, outputTexture.height, 1)
        
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        
        // Post-process: Blur for Realtime mode to fix slicing artifacts
        if quality == .realtime {
            // Create temp texture
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: outputTexture.pixelFormat, width: outputTexture.width, height: outputTexture.height, mipmapped: false)
            desc.usage = [.shaderRead, .shaderWrite]
            desc.storageMode = .private
            
            guard let blurTemp = context.device.makeTexture(descriptor: desc) else { return }
            
            var blurRadius: Float = 4.0 // Wide radius
            var qSettings = qualitySettings // Copy to var for pointer
            
            // Horizontal Blur
            guard let encoderH = context.commandBuffer.makeComputeCommandEncoder() else { return }
            encoderH.label = "Volumetric Blur H"
            encoderH.setComputePipelineState(blurHPipeline!)
            encoderH.setTexture(outputTexture, index: 0)
            encoderH.setTexture(blurTemp, index: 1)
            encoderH.setBytes(&blurRadius, length: MemoryLayout<Float>.size, index: 0)
            encoderH.setBytes(&qSettings, length: MemoryLayout<MVQualitySettings>.size, index: 1)
            
            let w = blurHPipeline!.threadExecutionWidth
            let h = blurHPipeline!.maxTotalThreadsPerThreadgroup / w
            let threadsPerGroup = MTLSizeMake(w, h, 1)
            let threadsPerGrid = MTLSizeMake(outputTexture.width, outputTexture.height, 1)
            
            encoderH.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
            encoderH.endEncoding()
            
            // Vertical Blur
            guard let encoderV = context.commandBuffer.makeComputeCommandEncoder() else { return }
            encoderV.label = "Volumetric Blur V"
            encoderV.setComputePipelineState(blurVPipeline!)
            encoderV.setTexture(blurTemp, index: 0)
            encoderV.setTexture(outputTexture, index: 1)
            encoderV.setBytes(&blurRadius, length: MemoryLayout<Float>.size, index: 0)
            encoderV.setBytes(&qSettings, length: MemoryLayout<MVQualitySettings>.size, index: 1)
            
            encoderV.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
            encoderV.endEncoding()
        }
    }
    
    private func buildPipeline(device: MTLDevice) throws {
        let library = ShaderLibrary(device: device)
        
        if (try? library.makeFunction(name: "fx_volumetric_light")) == nil {
             try? library.loadSource(resource: "MetaVisFXShaders")
        }
        
        // Load Blur shaders if needed
        if (try? library.makeFunction(name: "fx_blur_h")) == nil {
             try? library.loadSource(resource: "Blur")
        }
        
        let function = try library.makeFunction(name: "fx_volumetric_light")
        self.pipelineState = try device.makeComputePipelineState(function: function)
        
        self.blurHPipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "fx_blur_h"))
        self.blurVPipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "fx_blur_v"))
    }
}
