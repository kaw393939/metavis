import Metal
import MetalPerformanceShaders

public class ToneMapPass: RenderPass {
    public var label: String = "Tone Map Pass"
    
    private var pipelineState: MTLComputePipelineState?
    
    // Inputs
    public var inputTexture: MTLTexture?
    public var bloomTexture: MTLTexture?
    public var lutTexture: MTLTexture?
    
    // Configuration
    public var exposure: Float = 1.0
    public var saturation: Float = 1.0
    public var contrast: Float = 1.0
    public var vignetteIntensity: Float = 0.0
    public var filmGrainStrength: Float = 0.0
    public var bloomStrength: Float = 0.0
    
    // ODT / ToneMap
    public var tonemapOperator: UInt32 = 0 // 0: ACES
    public var odt: UInt32 = 1 // 1: sRGB
    
    public init() {}
    
    public func setup(device: MTLDevice, library: MTLLibrary) throws {
        guard let function = library.makeFunction(name: "final_composite") else {
            throw RenderError.shaderSourceNotFound("final_composite kernel not found")
        }
        self.pipelineState = try device.makeComputePipelineState(function: function)
    }
    
    public func execute(commandBuffer: MTLCommandBuffer, context: RenderContext) throws {
        guard let pipelineState = pipelineState,
              let input = inputTexture,
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }
        
        // Output is usually the context's render target
        // But `final_composite` is a Compute Kernel, so it needs a writable texture.
        // If the context output is a RenderPassDescriptor, we grab the texture from it.
        guard let output = context.renderPassDescriptor.colorAttachments[0].texture else {
            return
        }
        
        encoder.label = "Tone Map Compute"
        encoder.setComputePipelineState(pipelineState)
        
        encoder.setTexture(input, index: 0)
        encoder.setTexture(output, index: 1)
        
        // Optional Textures
        if let lut = lutTexture {
            encoder.setTexture(lut, index: 2)
        }
        
        if let bloom = bloomTexture {
            encoder.setTexture(bloom, index: 3)
        }
        
        // Buffers
        var vignetteVal = vignetteIntensity
        var vignetteSmooth = 0.5 // Default
        var grainVal = filmGrainStrength
        var lutInt = 1.0
        var hasLUTVal = (lutTexture != nil)
        var timeVal = Float(context.time)
        var letterboxVal: Float = 0.0
        var exposureVal = exposure
        var tmOp = tonemapOperator
        var satVal = saturation
        var conVal = contrast
        var odtVal = odt
        var debugVal: UInt32 = 0
        var validationVal: UInt32 = 0
        var bloomStr = bloomStrength
        var hasBloomVal = (bloomTexture != nil)
        
        encoder.setBytes(&vignetteVal, length: 4, index: 0)
        encoder.setBytes(&vignetteSmooth, length: 4, index: 1)
        encoder.setBytes(&grainVal, length: 4, index: 2)
        encoder.setBytes(&lutInt, length: 4, index: 3)
        encoder.setBytes(&hasLUTVal, length: 1, index: 4)
        encoder.setBytes(&timeVal, length: 4, index: 5)
        encoder.setBytes(&letterboxVal, length: 4, index: 6)
        encoder.setBytes(&exposureVal, length: 4, index: 7)
        encoder.setBytes(&tmOp, length: 4, index: 8)
        encoder.setBytes(&satVal, length: 4, index: 9)
        encoder.setBytes(&conVal, length: 4, index: 10)
        encoder.setBytes(&odtVal, length: 4, index: 11)
        encoder.setBytes(&debugVal, length: 4, index: 12)
        encoder.setBytes(&validationVal, length: 4, index: 13)
        encoder.setBytes(&bloomStr, length: 4, index: 14)
        encoder.setBytes(&hasBloomVal, length: 1, index: 15)
        
        let w = pipelineState.threadExecutionWidth
        let h = pipelineState.maxTotalThreadsPerThreadgroup / w
        let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
        let threadsPerGrid = MTLSize(width: output.width, height: output.height, depth: 1)
        
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
    }
}
