import Foundation
import Metal
import CoreMedia
import simd

/// Context passed down during the render pass.
public struct RenderContext {
    public let device: MTLDevice
    public let commandBuffer: MTLCommandBuffer
    public let time: CMTime
    public let resolution: SIMD2<Int>
    
    /// The current camera being used for rendering.
    public let camera: matrix_float4x4
    public let projection: matrix_float4x4
    
    public init(
        device: MTLDevice,
        commandBuffer: MTLCommandBuffer,
        time: CMTime,
        resolution: SIMD2<Int>,
        camera: matrix_float4x4,
        projection: matrix_float4x4
    ) {
        self.device = device
        self.commandBuffer = commandBuffer
        self.time = time
        self.resolution = resolution
        self.camera = camera
        self.projection = projection
    }
}
