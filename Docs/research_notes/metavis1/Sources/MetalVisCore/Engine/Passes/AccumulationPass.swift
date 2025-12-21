import Metal
import simd

public enum ShutterCurve {
    case box        // Standard digital shutter (constant weight)
    case triangle   // Mechanical shutter simulation (linear ramp)
    case gaussian   // Smooth electronic shutter / artistic
}

public class AccumulationPass: RenderPass {
    public var label: String = "Temporal Accumulation"
    public var inputs: [String] = ["main_buffer"]
    public var outputs: [String] = ["display_buffer"] // Writes to display buffer on resolve
    
    private var accumulatePipeline: MTLComputePipelineState?
    private var resolvePipeline: MTLComputePipelineState?
    
    // Persistent accumulation buffer
    private var accumulationTexture: MTLTexture?
    
    // Parameters are now derived from PhysicalCamera in RenderContext
    
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
        
        if accumulatePipeline == nil {
            try buildPipelines(device: context.device)
        }
        
        // 1. Create/Resize Accumulation Buffer if needed
        if accumulationTexture == nil ||
           accumulationTexture?.width != inputTexture.width ||
           accumulationTexture?.height != inputTexture.height {
            
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba32Float, // High precision for accumulation
                width: inputTexture.width,
                height: inputTexture.height,
                mipmapped: false
            )
            desc.usage = [.shaderRead, .shaderWrite]
            accumulationTexture = context.device.makeTexture(descriptor: desc)
            
            // Clear on create (or first subframe)
            clearTexture(context.commandBuffer, texture: accumulationTexture!)
        }
        
        // 2. Clear if first subframe
        if context.subframe == 0 {
            clearTexture(context.commandBuffer, texture: accumulationTexture!)
        }
        
        let commandBuffer = context.commandBuffer
        guard let accumTexture = accumulationTexture else { return }
        
        // 3. Calculate Weight
        let weight = calculateWeight(subframe: context.subframe, total: context.totalSubframes, camera: context.camera)
        
        // 4. Accumulate
        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.label = "Accumulate Subframe \(context.subframe)"
            encoder.setComputePipelineState(accumulatePipeline!)
            encoder.setTexture(inputTexture, index: 0)
            encoder.setTexture(accumTexture, index: 1)
            
            var w = weight
            encoder.setBytes(&w, length: MemoryLayout<Float>.size, index: 0)
            
            let width = accumulatePipeline!.threadExecutionWidth
            let height = accumulatePipeline!.maxTotalThreadsPerThreadgroup / width
            let threadsPerGroup = MTLSizeMake(width, height, 1)
            let threadsPerGrid = MTLSizeMake(inputTexture.width, inputTexture.height, 1)
            
            encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
            encoder.endEncoding()
        }
        
        // 5. Resolve (if last subframe)
        if context.subframe == context.totalSubframes - 1 {
            if let encoder = commandBuffer.makeComputeCommandEncoder() {
                encoder.label = "Resolve Accumulation"
                encoder.setComputePipelineState(resolvePipeline!)
                encoder.setTexture(accumTexture, index: 0)
                encoder.setTexture(outputTexture, index: 1)
                
                // Calculate total weight for normalization
                // We need to sum the weights of ALL subframes to normalize correctly
                // Since we don't store the sum, we re-calculate it.
                // Optimization: Pre-calculate total weight once per frame.
                var totalWeight: Float = 0
                for i in 0..<context.totalSubframes {
                    totalWeight += calculateWeight(subframe: i, total: context.totalSubframes, camera: context.camera)
                }
                
                encoder.setBytes(&totalWeight, length: MemoryLayout<Float>.size, index: 0)
                
                let width = resolvePipeline!.threadExecutionWidth
                let height = resolvePipeline!.maxTotalThreadsPerThreadgroup / width
                let threadsPerGroup = MTLSizeMake(width, height, 1)
                let threadsPerGrid = MTLSizeMake(outputTexture.width, outputTexture.height, 1)
                
                encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
                encoder.endEncoding()
            }
        }
    }
    
    private func calculateWeight(subframe: Int, total: Int, camera: PhysicalCamera) -> Float {
        if total <= 1 { return 1.0 }
        
        // Normalized time t in [0, 1]
        // Center of the interval for the subframe
        let t = (Float(subframe) + 0.5) / Float(total)
        
        // Shutter Angle Logic
        // 360 degrees = full frame duration (0.0 to 1.0)
        // 180 degrees = half frame duration (0.25 to 0.75)
        let openFraction = camera.shutterAngle / 360.0
        let start = 0.5 - (openFraction / 2.0)
        let end = 0.5 + (openFraction / 2.0)
        
        // If outside shutter open time, weight is 0
        if t < start || t > end {
            return 0.0
        }
        
        // Remap t to [0, 1] within the open interval
        let localT = (t - start) / (end - start)
        
        switch camera.shutterEfficiency {
        case .box:
            return 1.0
            
        case .trapezoidal:
            // 0 -> 1 -> 0 (Triangle/Trapezoid)
            // Simple triangle for now
            return 1.0 - abs(localT * 2.0 - 1.0)
            
        case .gaussian:
            // Bell curve centered at 0.5
            // exp(-((x-0.5)^2) / (2 * sigma^2))
            // Sigma = 0.15 gives a nice falloff
            let x = localT
            let sigma: Float = 0.15
            return exp(-pow(x - 0.5, 2) / (2 * sigma * sigma))
        }
    }
    
    private func clearTexture(_ commandBuffer: MTLCommandBuffer, texture: MTLTexture) {
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
            encoder.endEncoding()
        }
    }
    
    private func buildPipelines(device: MTLDevice) throws {
        let library = ShaderLibrary(device: device)
        
        // Ensure shaders are loaded
        if (try? library.makeFunction(name: "fx_accumulate")) == nil {
             try? library.loadSource(resource: "Effects/Temporal")
        }
        
        accumulatePipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "fx_accumulate"))
        resolvePipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "fx_resolve"))
    }
}
