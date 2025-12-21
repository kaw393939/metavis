import Foundation
import Metal

/// Manages the lifecycle of temporary textures used in the Render Graph.
/// Prevents expensive allocation/deallocation every frame.
public final class TexturePool: @unchecked Sendable {
    
    private let device: MTLDevice
    // private let commandQueue: MTLCommandQueue // Removed: Use caller's command buffer
    private var pool: [String: [MTLTexture]] = [:]
    private var accessTimes: [ObjectIdentifier: TimeInterval] = [:]
    private let lock = NSLock()
    
    /// Maximum number of textures to keep per descriptor type
    private let maxTexturesPerType: Int
    
    public init(device: MTLDevice, maxTexturesPerType: Int = 10) {
        self.device = device
        self.maxTexturesPerType = maxTexturesPerType
        // Removed: self.commandQueue = ...
    }
    
    /// Requests a texture with the specified descriptor.
    /// - Parameter descriptor: The texture properties.
    /// - Parameter commandBuffer: The command buffer to use for clearing the texture.
    /// - Returns: A reusable texture or a new one if none are available.
    public func requestTexture(descriptor: MTLTextureDescriptor, commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        let key = cacheKey(for: descriptor)
        
        var textureToReturn: MTLTexture?
        
        lock.lock()
        if var textures = pool[key], !textures.isEmpty {
            let texture = textures.removeLast()
            pool[key] = textures
            
            // Update access time
            accessTimes[ObjectIdentifier(texture)] = Date().timeIntervalSince1970
            
            textureToReturn = texture
        }
        lock.unlock()
        
        if textureToReturn == nil {
            // No texture found, create a new one
            if let newTexture = device.makeTexture(descriptor: descriptor) {
                accessTimes[ObjectIdentifier(newTexture)] = Date().timeIntervalSince1970
                textureToReturn = newTexture
            }
        }
        
        // CRITICAL: Clear the texture using the SAME command buffer as the render pass
        if let texture = textureToReturn {
            clearTexture(texture, commandBuffer: commandBuffer)
        }
        
        return textureToReturn
    }
    
    /// Clears a texture to transparent black using the provided command buffer
    private func clearTexture(_ texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        let renderPass = MTLRenderPassDescriptor()
        renderPass.colorAttachments[0].texture = texture
        renderPass.colorAttachments[0].loadAction = .clear
        renderPass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        renderPass.colorAttachments[0].storeAction = .store
        
        // Create encoder on the provided command buffer
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) {
            encoder.label = "TexturePool Clear"
            encoder.endEncoding()
        }
    }
    
    /// Returns a texture to the pool for reuse.
    /// - Parameter texture: The texture to release.
    public func returnTexture(_ texture: MTLTexture) {
        let descriptor = descriptor(for: texture)
        let key = cacheKey(for: descriptor)
        
        lock.lock()
        defer { lock.unlock() }
        
        if pool[key] == nil {
            pool[key] = []
        }
        
        // Check if we need to evict old textures (LRU)
        if var textures = pool[key], textures.count >= maxTexturesPerType {
            // Find least recently used texture
            var oldestTexture: MTLTexture?
            var oldestTime: TimeInterval = .infinity
            
            for pooledTexture in textures {
                let id = ObjectIdentifier(pooledTexture)
                let time = accessTimes[id] ?? 0
                if time < oldestTime {
                    oldestTime = time
                    oldestTexture = pooledTexture
                }
            }
            
            // Remove LRU texture
            if let toRemove = oldestTexture,
               let index = textures.firstIndex(where: { $0 === toRemove }) {
                textures.remove(at: index)
                accessTimes.removeValue(forKey: ObjectIdentifier(toRemove))
                pool[key] = textures
            }
        }
        
        // Add texture to pool
        pool[key]?.append(texture)
        accessTimes[ObjectIdentifier(texture)] = Date().timeIntervalSince1970
    }
    
    /// Clears all pooled textures (call at end of frame if needed)
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        
        pool.removeAll()
        accessTimes.removeAll()
    }
    
    // MARK: - Helpers
    
    private func cacheKey(for descriptor: MTLTextureDescriptor) -> String {
        return "\(descriptor.pixelFormat.rawValue)_\(descriptor.width)x\(descriptor.height)_\(descriptor.usage.rawValue)"
    }
    
    private func descriptor(for texture: MTLTexture) -> MTLTextureDescriptor {
        let desc = MTLTextureDescriptor()
        desc.pixelFormat = texture.pixelFormat
        desc.width = texture.width
        desc.height = texture.height
        desc.usage = texture.usage
        return desc
    }
}
