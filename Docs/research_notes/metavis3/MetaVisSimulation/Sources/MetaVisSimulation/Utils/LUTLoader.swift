import Foundation
import Metal
import MetalKit

public enum LUTError: Error {
    case fileNotFound
    case invalidFormat
    case unsupportedSize
    case deviceError
}

public class LUTLoader {
    private let device: MTLDevice
    
    public init(device: MTLDevice) {
        self.device = device
    }
    
    /// Loads a .cube file from a URL and creates a 3D Metal Texture.
    /// Supports standard Adobe Cube format (RGB float values).
    public func loadCubeLUT(url: URL) throws -> MTLTexture {
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        
        var size: Int = 0
        var data: [Float] = []
        var domainMin = SIMD3<Float>(0, 0, 0)
        var domainMax = SIMD3<Float>(1, 1, 1)
        
        // Parse Header
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            
            if trimmed.hasPrefix("LUT_3D_SIZE") {
                let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if parts.count >= 2, let s = Int(parts[1]) {
                    size = s
                }
            } else if trimmed.hasPrefix("DOMAIN_MIN") {
                let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if parts.count >= 4 {
                    domainMin = SIMD3<Float>(Float(parts[1]) ?? 0, Float(parts[2]) ?? 0, Float(parts[3]) ?? 0)
                }
            } else if trimmed.hasPrefix("DOMAIN_MAX") {
                let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if parts.count >= 4 {
                    domainMax = SIMD3<Float>(Float(parts[1]) ?? 1, Float(parts[2]) ?? 1, Float(parts[3]) ?? 1)
                }
            } else if trimmed.hasPrefix("TITLE") {
                continue
            } else {
                // Parse Data
                let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if parts.count == 3 {
                    if let r = Float(parts[0]), let g = Float(parts[1]), let b = Float(parts[2]) {
                        data.append(r)
                        data.append(g)
                        data.append(b)
                        data.append(1.0) // Alpha
                    }
                }
            }
        }
        
        guard size > 0 else { throw LUTError.invalidFormat }
        guard data.count == size * size * size * 4 else {
            print("LUT Data Count Mismatch: Expected \(size*size*size*4), got \(data.count)")
            throw LUTError.invalidFormat
        }
        
        // Create Texture
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .rgba32Float // High precision for LUTs
        descriptor.width = size
        descriptor.height = size
        descriptor.depth = size
        descriptor.usage = .shaderRead
        
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw LUTError.deviceError
        }
        
        let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                               size: MTLSize(width: size, height: size, depth: size))
        
        // Upload data
        // 3D Texture layout: R changes fastest, then G, then B
        // .cube format: R changes fastest, then G, then B. Matches!
        
        data.withUnsafeBytes { buffer in
            if let ptr = buffer.baseAddress {
                texture.replace(region: region,
                                mipmapLevel: 0,
                                slice: 0,
                                withBytes: ptr,
                                bytesPerRow: size * 4 * MemoryLayout<Float>.size,
                                bytesPerImage: size * size * 4 * MemoryLayout<Float>.size)
            }
        }
        
        return texture
    }
}
