import Foundation
import Metal

public class LUTLoader {
    public enum LUTError: Error {
        case fileNotFound
        case invalidFormat
        case unsupportedSize
        case textureCreationFailure
    }

    /// Loads a .cube file into a 3D Metal Texture
    public static func loadCubeFile(url: URL, device: MTLDevice) throws -> MTLTexture {
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)

        var size = 0
        var data: [Float] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("TITLE") {
                continue
            }

            if trimmed.hasPrefix("LUT_3D_SIZE") {
                let parts = trimmed.components(separatedBy: .whitespaces)
                if parts.count >= 2, let s = Int(parts.last!) {
                    size = s
                }
                continue
            }

            // Parse RGB values
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

        guard size > 0 else {
            throw LUTError.invalidFormat
        }

        guard data.count == size * size * size * 4 else {
            throw LUTError.invalidFormat
        }

        return try createTexture(from: data, size: size, device: device)
    }

    /// Generates a procedural "Teal & Orange" look LUT
    public static func generateTealOrangeLUT(size: Int, device: MTLDevice) throws -> MTLTexture {
        var data: [Float] = []
        data.reserveCapacity(size * size * size * 4)

        let invSize = 1.0 / Float(size - 1)

        for z in 0 ..< size {
            for y in 0 ..< size {
                for x in 0 ..< size {
                    let r = Float(x) * invSize
                    let g = Float(y) * invSize
                    let b = Float(z) * invSize

                    // Apply Teal & Orange transformation
                    // Shadows -> Teal, Highlights -> Orange

                    let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b

                    // Push shadows towards teal (minus red, plus blue/green)
                    var newR = r + (luminance - 0.5) * 0.2 // Boost red in highlights
                    var newG = g + (0.5 - luminance) * 0.1 // Boost green in shadows
                    var newB = b - (luminance - 0.5) * 0.2 // Reduce blue in highlights

                    // Contrast curve
                    newR = (newR - 0.5) * 1.1 + 0.5
                    newG = (newG - 0.5) * 1.1 + 0.5
                    newB = (newB - 0.5) * 1.1 + 0.5

                    data.append(max(0, min(1, newR)))
                    data.append(max(0, min(1, newG)))
                    data.append(max(0, min(1, newB)))
                    data.append(1.0)
                }
            }
        }

        return try createTexture(from: data, size: size, device: device)
    }

    private static func createTexture(from data: [Float], size: Int, device: MTLDevice) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.width = size
        descriptor.height = size
        descriptor.depth = size
        descriptor.pixelFormat = .rgba32Float
        descriptor.usage = .shaderRead

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw LUTError.textureCreationFailure
        }

        let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                               size: MTLSize(width: size, height: size, depth: size))

        data.withUnsafeBytes { buffer in
            texture.replace(region: region,
                            mipmapLevel: 0,
                            slice: 0,
                            withBytes: buffer.baseAddress!,
                            bytesPerRow: size * MemoryLayout<Float>.size * 4,
                            bytesPerImage: size * size * MemoryLayout<Float>.size * 4)
        }

        return texture
    }
}
