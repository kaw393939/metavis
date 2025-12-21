import Metal
import simd

public class PBRPass: @unchecked Sendable {
    
    public let device: MTLDevice
    private let pipeline: MTLComputePipelineState
    private let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
    
    public init(device: MTLDevice) throws {
        self.device = device
        
        let library = try ShaderLibrary.loadDefaultLibrary(device: device)
        
        guard let function = library.makeFunction(name: "pbr_render") else {
            throw PBRPassError.shaderNotFound
        }
        
        self.pipeline = try device.makeComputePipelineState(function: function)
    }
    
    public func render(
        output: MTLTexture,
        color: SIMD3<Float>,
        roughness: Float,
        metallic: Float,
        commandBuffer: MTLCommandBuffer
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "PBR Render"
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(output, index: 0)
        
        var c = color
        var r = roughness
        var m = metallic
        
        encoder.setBytes(&c, length: MemoryLayout<SIMD3<Float>>.size, index: 0)
        encoder.setBytes(&r, length: MemoryLayout<Float>.size, index: 1)
        encoder.setBytes(&m, length: MemoryLayout<Float>.size, index: 2)
        
        let groups = MTLSize(
            width: (output.width + threadGroupSize.width - 1) / threadGroupSize.width,
            height: (output.height + threadGroupSize.height - 1) / threadGroupSize.height,
            depth: 1
        )
        encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()
    }
}

enum PBRPassError: Error {
    case shaderNotFound
}
