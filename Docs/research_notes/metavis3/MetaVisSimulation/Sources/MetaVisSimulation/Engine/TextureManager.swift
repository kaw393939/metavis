import Foundation
import Metal
import MetalKit

public protocol TextureProvider {
    func texture(for assetId: UUID) -> MTLTexture?
}

public class TextureManager: TextureProvider {
    private let device: MTLDevice
    private let textureLoader: MTKTextureLoader
    private var cache: [UUID: MTLTexture] = [:]
    
    public init(device: MTLDevice) {
        self.device = device
        self.textureLoader = MTKTextureLoader(device: device)
    }
    
    public func texture(for assetId: UUID) -> MTLTexture? {
        return cache[assetId]
    }
    
    public func loadTexture(url: URL, for assetId: UUID) throws {
        let texture = try textureLoader.newTexture(URL: url, options: [
            .origin: MTKTextureLoader.Origin.topLeft,
            .SRGB: false
        ])
        cache[assetId] = texture
    }
    
    public func register(texture: MTLTexture, for assetId: UUID) {
        cache[assetId] = texture
    }
}
