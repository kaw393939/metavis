import Foundation
import CoreGraphics
import Metal

public struct StableGlyphKey: Hashable, Codable, Sendable {
    public let fontName: String
    public let fontSize: CGFloat
    public let glyphIndex: CGGlyph
    
    public init(fontName: String, fontSize: CGFloat, glyphIndex: CGGlyph) {
        self.fontName = fontName
        self.fontSize = fontSize
        self.glyphIndex = glyphIndex
    }
    
    // Custom hashing/equality if needed, but default is fine
}

// Helper for dictionary key encoding
extension StableGlyphKey: CustomStringConvertible {
    public var description: String {
        return "\(fontName)-\(fontSize)-\(glyphIndex)"
    }
}

public struct GlyphCacheManifest: Codable, Sendable {
    public let version: Int
    public var entries: [StableGlyphKey: GlyphAtlasLocation]
    public var atlasState: GlyphAtlasBuilder.State?
    
    public init(version: Int = 1, entries: [StableGlyphKey: GlyphAtlasLocation] = [:], atlasState: GlyphAtlasBuilder.State? = nil) {
        self.version = version
        self.entries = entries
        self.atlasState = atlasState
    }
}

public class GlyphCacheStore {
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let manifestURL: URL
    private let textureURL: URL
    
    public init() throws {
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        self.cacheDirectory = paths[0].appendingPathComponent("MetaVisRender/Glyphs")
        try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        self.manifestURL = cacheDirectory.appendingPathComponent("manifest.json")
        self.textureURL = cacheDirectory.appendingPathComponent("atlas.data") // Raw bytes for now
    }
    
    public func loadManifest() -> GlyphCacheManifest? {
        guard let data = try? Data(contentsOf: manifestURL) else { return nil }
        return try? JSONDecoder().decode(GlyphCacheManifest.self, from: data)
    }
    
    public func saveManifest(_ manifest: GlyphCacheManifest) {
        if let data = try? JSONEncoder().encode(manifest) {
            try? data.write(to: manifestURL)
        }
    }
    
    public func loadTexture(device: MTLDevice, descriptor: MTLTextureDescriptor) -> MTLTexture? {
        guard let data = try? Data(contentsOf: textureURL) else { return nil }
        
        // Verify size matches descriptor
        // Assuming r8Unorm (1 byte per pixel)
        let expectedSize = descriptor.width * descriptor.height
        guard data.count == expectedSize else {
            print("Cache texture size mismatch. Expected \(expectedSize), got \(data.count)")
            return nil
        }
        
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        
        data.withUnsafeBytes { buffer in
            if let baseAddress = buffer.baseAddress {
                let region = MTLRegionMake2D(0, 0, descriptor.width, descriptor.height)
                texture.replace(region: region, mipmapLevel: 0, withBytes: baseAddress, bytesPerRow: descriptor.width)
            }
        }
        
        return texture
    }
    
    public func saveTexture(_ texture: MTLTexture) {
        let width = texture.width
        let height = texture.height
        let bytesPerRow = width // r8Unorm
        var data = Data(count: width * height)
        
        data.withUnsafeMutableBytes { buffer in
            if let baseAddress = buffer.baseAddress {
                let region = MTLRegionMake2D(0, 0, width, height)
                texture.getBytes(baseAddress, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
            }
        }
        
        try? data.write(to: textureURL)
    }
    
    public func clear() {
        try? fileManager.removeItem(at: manifestURL)
        try? fileManager.removeItem(at: textureURL)
    }
}
