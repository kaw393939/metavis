import Foundation
import Metal

public enum LIGMMode: String, Codable, Sendable {
    case noise
    case checkerboard
    case gradient
    case macbeth
}

public struct LIGMRequest: Sendable, Codable {
    public let mode: LIGMMode
    public let width: Int
    public let height: Int
    public let seed: Int
    public let camera: VirtualCamera?
    
    public init(mode: LIGMMode, width: Int, height: Int, seed: Int, camera: VirtualCamera? = nil) {
        self.mode = mode
        self.width = width
        self.height = height
        self.seed = seed
        self.camera = camera
    }
}

public struct LIGMResponse: Sendable {
    public let texture: MTLTexture
    public let metadata: [String: String]
}

public actor LIGM {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    
    public init(device: MTLDevice) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
    }
    
    public func generate(request: LIGMRequest) async throws -> LIGMResponse {
        // Placeholder for actual Metal compute shader execution
        // In a real implementation, we would:
        // 1. Create a texture descriptor
        // 2. Create a compute pipeline state
        // 3. Dispatch threads
        
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, // ACEScg linear usually needs float16
            width: request.width,
            height: request.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw NSError(domain: "LIGM", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create texture"])
        }
        
        if request.mode == .macbeth || request.mode == .gradient {
            do {
                // Use the Registry to load the pipeline
                let shaderName = request.mode == .macbeth ? "macbeth_generator" : "gradient_generator"
                let pipeline = try await ShaderRegistry.shared.loadCompute(name: shaderName, device: device)
                
                guard let commandBuffer = commandQueue.makeCommandBuffer(),
                      let encoder = commandBuffer.makeComputeCommandEncoder() else {
                    throw NSError(domain: "LIGM", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create command encoder"])
                }
                
                encoder.setComputePipelineState(pipeline)
                encoder.setTexture(texture, index: 0)
                
                let w = pipeline.threadExecutionWidth
                let h = pipeline.maxTotalThreadsPerThreadgroup / w
                let threadsPerThreadgroup = MTLSizeMake(w, h, 1)
                let threadsPerGrid = MTLSizeMake(request.width, request.height, 1)
                
                encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
                encoder.endEncoding()
                
                await withCheckedContinuation { continuation in
                    commandBuffer.addCompletedHandler { _ in
                        continuation.resume()
                    }
                    commandBuffer.commit()
                }
            } catch {
                print("⚠️ LIGM GPU Error: \(error). Falling back to simulation.")
                // Fallback or rethrow? For now, let's rethrow to see the error.
                throw error
            }
        } else {
            // Simulate work
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        
        return LIGMResponse(texture: texture, metadata: ["mode": request.mode.rawValue])
    }
}
