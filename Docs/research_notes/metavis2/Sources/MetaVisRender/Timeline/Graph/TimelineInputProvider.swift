import Metal
import Foundation

public class TimelineInputProvider: InputProvider {
    private var currentTextures: [String: MTLTexture] = [:]
    
    public init() {}
    
    public func update(textures: [String: MTLTexture]) {
        self.currentTextures = textures
    }
    
    public func texture(for assetId: String, time: Double) -> MTLTexture? {
        return currentTextures[assetId]
    }
}
