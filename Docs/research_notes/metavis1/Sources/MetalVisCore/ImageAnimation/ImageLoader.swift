import CoreGraphics
import Foundation
import ImageIO
@preconcurrency import Metal

/// Loads images from filesystem and converts them to Metal textures
/// Supports both eager and lazy (promise-based) loading
public struct ImageLoader: Sendable {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    public init(device: MTLDevice, commandQueue: MTLCommandQueue) {
        self.device = device
        self.commandQueue = commandQueue
    }

    /// Load an image from a file path and convert to Metal texture
    /// Supports: PNG, JPEG, TIFF, BMP
    /// - Parameters:
    ///   - path: File path to image
    ///   - alphaType: Desired alpha type for texture (default: premultiplied)
    /// - Returns: Metal texture with specified alpha type
    public func loadTexture(from path: String, alphaType: AlphaType = .premultiplied) throws -> MTLTexture {
        let url = URL(fileURLWithPath: path)

        // Load image using ImageIO for maximum compatibility
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageLoaderError.fileNotFound(path)
        }

        guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw ImageLoaderError.unableToLoadImage(path)
        }

        return try createTexture(from: cgImage, alphaType: alphaType)
    }

    /// Create Metal texture from CGImage with mipmapping for Ken Burns quality (MBE Chapter 7)
    /// - Parameters:
    ///   - cgImage: Source CGImage
    ///   - alphaType: Desired alpha type (default: premultiplied)
    private func createTexture(from cgImage: CGImage, alphaType: AlphaType = .premultiplied) throws -> MTLTexture {
        let width = cgImage.width
        let height = cgImage.height

        // Create texture descriptor with mipmapping enabled (MBE page 65)
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: true // Enable mipmaps for smooth zoom/pan
        )
        // renderTarget needed for blit encoder mipmap generation (MBE page 67)
        textureDescriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]

        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            throw ImageLoaderError.unableToCreateTexture
        }

        // Create bitmap context and copy pixel data
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width

        // Set bitmap info based on desired alpha type
        let bitmapInfo: CGBitmapInfo
        switch alphaType {
        case .premultiplied:
            bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        case .straight:
            bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
        case .opaque:
            bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
        }

        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw ImageLoaderError.unableToCreateBitmapContext
        }

        // Flip coordinate system to match Metal's texture coordinates
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        // Draw image into context
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Copy pixel data to texture (base mip level 0)
        let region = MTLRegionMake2D(0, 0, width, height)
        texture.replace(
            region: region,
            mipmapLevel: 0,
            withBytes: pixelData,
            bytesPerRow: bytesPerRow
        )

        // Generate remaining mip levels using GPU blit encoder (MBE page 67)
        // This is ~10x faster than CPU generation and takes ~1ms for 1024x1024 on A8
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let blitEncoder = commandBuffer.makeBlitCommandEncoder()
        else {
            throw ImageLoaderError.unableToGenerateMipmaps
        }

        blitEncoder.generateMipmaps(for: texture)
        blitEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        return texture
    }

    /// Export Metal texture to PNG file
    public func exportTexture(_ texture: MTLTexture, to path: String) throws {
        let width = texture.width
        let height = texture.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width

        // Read texture data
        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        let region = MTLRegionMake2D(0, 0, width, height)
        texture.getBytes(
            &pixelData,
            bytesPerRow: bytesPerRow,
            from: region,
            mipmapLevel: 0
        )

        // Create CGImage from pixel data
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let provider = CGDataProvider(
            data: Data(pixelData) as CFData
        ) else {
            throw ImageLoaderError.unableToCreateDataProvider
        }

        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            throw ImageLoaderError.unableToCreateCGImage
        }

        // Write to PNG file
        let url = URL(fileURLWithPath: path)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            "public.png" as CFString,
            1,
            nil
        ) else {
            throw ImageLoaderError.unableToCreateImageDestination(path)
        }

        CGImageDestinationAddImage(destination, cgImage, nil)

        if !CGImageDestinationFinalize(destination) {
            throw ImageLoaderError.unableToWriteImage(path)
        }
    }
}

// MARK: - Errors

public enum ImageLoaderError: Error, CustomStringConvertible {
    case fileNotFound(String)
    case unableToLoadImage(String)
    case unableToCreateTexture
    case unableToCreateBitmapContext
    case unableToCreateDataProvider
    case unableToCreateCGImage
    case unableToCreateImageDestination(String)
    case unableToWriteImage(String)
    case unableToGenerateMipmaps

    public var description: String {
        switch self {
        case let .fileNotFound(path):
            return "Image file not found: \(path)"
        case let .unableToLoadImage(path):
            return "Unable to load image: \(path)"
        case .unableToCreateTexture:
            return "Unable to create Metal texture"
        case .unableToCreateBitmapContext:
            return "Unable to create bitmap context"
        case .unableToCreateDataProvider:
            return "Unable to create data provider"
        case .unableToCreateCGImage:
            return "Unable to create CGImage"
        case let .unableToCreateImageDestination(path):
            return "Unable to create image destination: \(path)"
        case let .unableToWriteImage(path):
            return "Unable to write image: \(path)"
        case .unableToGenerateMipmaps:
            return "Unable to generate mipmaps with blit encoder"
        }
    }
}
