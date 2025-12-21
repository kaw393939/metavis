import Metal
import MetalPerformanceShaders

public class BloomPass: RenderPass {
    public var label: String = "Bloom Pass"
    
    private var downsamplePipeline: MTLComputePipelineState?
    private var upsamplePipeline: MTLComputePipelineState?
    
    /// Cached threadgroup size for optimal dispatch
    private var optimalThreadgroupSize: MTLSize = MTLSize(width: 16, height: 16, depth: 1)
    
    // Inputs/Outputs
    public var inputTexture: MTLTexture?
    public var resultTexture: MTLTexture?
    
    // Configuration
    public var intensity: Float = 1.0
    public var threshold: Float = 1.0
    public var knee: Float = 0.5
    
    public init() {}
    
    public func setup(device: MTLDevice, library: MTLLibrary) throws {
        guard let downsampleFunction = library.makeFunction(name: "bloom_downsample"),
              let upsampleFunction = library.makeFunction(name: "bloom_upsample") else {
            throw RenderError.shaderSourceNotFound("Bloom kernels not found")
        }
        
        self.downsamplePipeline = try device.makeComputePipelineState(function: downsampleFunction)
        self.upsamplePipeline = try device.makeComputePipelineState(function: upsampleFunction)
        
        // Calculate optimal threadgroup size for this device
        if let pipeline = downsamplePipeline {
            let w = pipeline.threadExecutionWidth
            let h = pipeline.maxTotalThreadsPerThreadgroup / w
            optimalThreadgroupSize = MTLSize(width: w, height: h, depth: 1)
        }
    }
    
    public func execute(commandBuffer: MTLCommandBuffer, context: RenderContext) throws {
        guard let input = inputTexture,
              let downsamplePipeline = downsamplePipeline,
              let upsamplePipeline = upsamplePipeline,
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }
        
        encoder.label = "Bloom Compute"
        encoder.pushDebugGroup("Bloom Pass")
        
        let mipLevels = Int(context.quality.bloomMipLevels)
        var mipTextures: [MTLTexture] = []
        
        // 1. Downsample Chain
        var currentSource = input
        
        for i in 0..<mipLevels {
            let width = max(1, currentSource.width / 2)
            let height = max(1, currentSource.height / 2)
            
            // OPTIMIZATION: Use intermediate pool for GPU-only textures
            // These don't need CPU access so .private is optimal
            guard let dest = context.texturePool.acquireIntermediate(
                pixelFormat: .rgba16Float,
                width: width,
                height: height,
                usage: [.shaderRead, .shaderWrite]
            ) else { break }
            
            mipTextures.append(dest)
            
            encoder.setComputePipelineState(downsamplePipeline)
            encoder.setTexture(currentSource, index: 0)
            encoder.setTexture(dest, index: 1)
            
            // Uniforms
            var thresholdVal = (i == 0) ? threshold : 0.0 // Only apply threshold on first pass
            var kneeVal = knee
            
            encoder.setBytes(&thresholdVal, length: MemoryLayout<Float>.size, index: 0)
            encoder.setBytes(&kneeVal, length: MemoryLayout<Float>.size, index: 1)
            
            dispatchOptimal(encoder: encoder, pipeline: downsamplePipeline, width: width, height: height)
            
            currentSource = dest
        }
        
        // 2. Upsample Chain (Accumulate)
        encoder.setComputePipelineState(upsamplePipeline)
        
        for i in (0..<mipTextures.count - 1).reversed() {
            let source = mipTextures[i + 1]
            let dest = mipTextures[i]
            
            encoder.setTexture(source, index: 0)
            encoder.setTexture(dest, index: 1) // Read-Write
            
            var radius: Float = 1.0 // Filter radius
            encoder.setBytes(&radius, length: MemoryLayout<Float>.size, index: 0)
            
            dispatchOptimal(encoder: encoder, pipeline: upsamplePipeline, width: dest.width, height: dest.height)
        }
        
        encoder.popDebugGroup()
        encoder.endEncoding()
        
        // 3. Cleanup - Return textures to pool
        if let oldResult = resultTexture {
            context.texturePool.return(oldResult)
        }
        
        if !mipTextures.isEmpty {
            resultTexture = mipTextures[0]
            
            // Return intermediate textures immediately
            for i in 1..<mipTextures.count {
                context.texturePool.return(mipTextures[i])
            }
        }
    }
    
    /// Dispatches compute work with optimal threadgroup sizing for the device
    private func dispatchOptimal(encoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState, width: Int, height: Int) {
        let threadsPerGrid = MTLSize(width: width, height: height, depth: 1)
        
        // Use non-uniform dispatch for better efficiency on partial tiles
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: optimalThreadgroupSize)
    }
    
    /// Legacy dispatch method for compatibility
    private func dispatch(encoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState, width: Int, height: Int) {
        let w = pipeline.threadExecutionWidth
        let h = pipeline.maxTotalThreadsPerThreadgroup / w
        let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
        let threadsPerGrid = MTLSize(width: width, height: height, depth: 1)
        
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    }
}
