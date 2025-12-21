import Metal
import CoreVideo
import CoreImage
import CoreGraphics
import UniformTypeIdentifiers

public struct TextureUtils {
    
    /// Export a Metal texture directly to PNG file for debugging
    /// - Parameters:
    ///   - texture: Source Metal texture (any format)
    ///   - path: Output file path
    /// - Returns: True if successful
    public static func textureToPNG(_ texture: MTLTexture, path: String) -> Bool {
        let width = texture.width
        let height = texture.height
        
        // Convert texture to RGBA8 if needed
        var sourceTexture = texture
        if texture.pixelFormat != .rgba8Unorm && texture.pixelFormat != .bgra8Unorm {
            // Need to convert - create temp texture
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: width,
                height: height,
                mipmapped: false
            )
            descriptor.usage = [.shaderWrite, .shaderRead, .renderTarget]
            
            let device = texture.device
            guard let tempTexture = device.makeTexture(descriptor: descriptor),
                  let commandQueue = device.makeCommandQueue(),
                  let commandBuffer = commandQueue.makeCommandBuffer() else {
                print("❌ Failed to create conversion resources")
                return false
            }
            
            // Use CIImage to convert formats
            let ciContext = CIContext(mtlDevice: device)
            let ciImage = CIImage(mtlTexture: texture)!
            ciContext.render(ciImage, to: tempTexture, commandBuffer: commandBuffer, bounds: CGRect(x: 0, y: 0, width: width, height: height), colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            
            sourceTexture = tempTexture
        }
        
        // Read bytes from texture
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let bufferSize = bytesPerRow * height
        var pixels = [UInt8](repeating: 0, count: bufferSize)
        
        let region = MTLRegionMake2D(0, 0, width, height)
        sourceTexture.getBytes(&pixels, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        
        // Create CGImage
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo: CGBitmapInfo = sourceTexture.pixelFormat == .bgra8Unorm 
            ? CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            : CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            print("❌ Failed to create CGImage")
            return false
        }
        
        // Write PNG
        let url = URL(fileURLWithPath: path)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            print("❌ Failed to create image destination")
            return false
        }
        
        CGImageDestinationAddImage(destination, cgImage, nil)
        let success = CGImageDestinationFinalize(destination)
        
        if success {
            print("✅ Exported texture to: \(path)")
        } else {
            print("❌ Failed to write PNG")
        }
        
        return success
    }
    
    /// Converts a Metal texture to a CVPixelBuffer.
    /// - Parameters:
    ///   - texture: The source Metal texture.
    ///   - width: The width of the output buffer.
    ///   - height: The height of the output buffer.
    ///   - colorSpace: The color space (e.g., "rec709", "srgb").
    /// - Returns: A CVPixelBuffer containing the texture data, or nil if conversion fails.
    public static func textureToPixelBuffer(_ texture: MTLTexture, width: Int, height: Int, colorSpace: String = "rec709") -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        
        let attributes: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &pixelBuffer)
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        // Lock the base address
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            return nil
        }
        
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let region = MTLRegionMake2D(0, 0, width, height)
        
        // Copy bytes from texture to pixel buffer
        // Note: This assumes the texture format matches (BGRA8Unorm).
        // If the texture is RGBA, we might need to swizzle or use a blit encoder.
        // For now, assuming the render output is BGRA8Unorm as set in RenderPassDescriptor.
        
        texture.getBytes(baseAddress, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        
        return buffer
    }
}
