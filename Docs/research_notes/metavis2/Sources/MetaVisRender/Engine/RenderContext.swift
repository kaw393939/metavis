import Foundation
import Metal

public struct RenderContext {
    public let device: MTLDevice
    public let commandBuffer: MTLCommandBuffer
    public let renderPassDescriptor: MTLRenderPassDescriptor
    public let resolution: SIMD2<Int>
    public let time: Double
    public let scene: Scene
    public let quality: MVQualitySettings
    public let texturePool: TexturePool
    public let inputProvider: InputProvider?
    
    public init(
        device: MTLDevice,
        commandBuffer: MTLCommandBuffer,
        renderPassDescriptor: MTLRenderPassDescriptor,
        resolution: SIMD2<Int>,
        time: Double,
        scene: Scene,
        quality: MVQualitySettings = MVQualitySettings(mode: .realtime),
        texturePool: TexturePool,
        inputProvider: InputProvider? = nil
    ) {
        self.device = device
        self.commandBuffer = commandBuffer
        self.renderPassDescriptor = renderPassDescriptor
        self.resolution = resolution
        self.time = time
        self.scene = scene
        self.quality = quality
        self.texturePool = texturePool
        self.inputProvider = inputProvider
    }
}

public protocol InputProvider {
    func texture(for assetId: String, time: Double) -> MTLTexture?
}
