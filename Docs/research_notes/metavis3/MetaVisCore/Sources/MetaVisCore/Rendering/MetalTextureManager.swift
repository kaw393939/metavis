import Metal
import Foundation

/// Manages Metal resources and texture creation for the rendering pipeline.
/// Optimized for Apple Silicon (Unified Memory).
public class MetalTextureManager {
    
    public static let shared = MetalTextureManager()
    
    public let device: MTLDevice?
    public let commandQueue: MTLCommandQueue?
    
    private init() {
        self.device = MTLCreateSystemDefaultDevice()
        self.commandQueue = self.device?.makeCommandQueue()
    }
    
    /// Creates a Metal texture from a FITSAsset.
    /// Uses .r32Float format for high dynamic range data.
    public func createTexture(from asset: FITSAsset) -> MTLTexture? {
        guard let device = device else { return nil }
        
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float,
            width: asset.width,
            height: asset.height,
            mipmapped: false
        )
        
        // Usage: Read by shaders (ToneMap), Written by CPU (initial upload)
        descriptor.usage = [.shaderRead] 
        
        // Storage Mode: Shared is optimal for Apple Silicon for CPU->GPU one-off uploads
        // If we were doing heavy GPU-only processing, we might blit to .private,
        // but for a read-once-per-frame source texture, .shared is efficient.
        descriptor.storageMode = .shared
        
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        
        let region = MTLRegionMake2D(0, 0, asset.width, asset.height)
        let bytesPerRow = asset.width * 4 // 4 bytes per Float32
        
        asset.rawData.withUnsafeBytes { bufferPointer in
            if let baseAddress = bufferPointer.baseAddress {
                texture.replace(
                    region: region,
                    mipmapLevel: 0,
                    withBytes: baseAddress,
                    bytesPerRow: bytesPerRow
                )
            }
        }
        
        return texture
    }
    
    /// Creates an empty output texture (e.g. for the composition result).
    /// Uses .rgba16Float (half-float) for ACEScg linear data, saving bandwidth vs 32-bit.
    public func createOutputTexture(width: Int, height: Int) -> MTLTexture? {
        guard let device = device else { return nil }
        
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            mipmapped: false
        )
        
        // Usage: Written by Compute Kernel, Read by View (or next pass)
        descriptor.usage = [.shaderWrite, .shaderRead]
        descriptor.storageMode = .private // GPU only
        
        return device.makeTexture(descriptor: descriptor)
    }
}
