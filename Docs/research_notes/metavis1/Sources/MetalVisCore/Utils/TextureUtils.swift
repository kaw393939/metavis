import CoreVideo
import Foundation
import Metal

/// Utilities for Metal texture operations
public enum TextureUtils {
    /// Convert a Metal texture to a CVPixelBuffer for video encoding
    ///
    /// This captures the GPU texture data into CPU-accessible memory, preventing
    /// GPU memory reuse issues that can occur when textures are queued for encoding.
    ///
    /// - Parameters:
    ///   - texture: Source Metal texture (must be RGBA8Unorm, BGRA8Unorm, or RGBA16Float)
    ///   - width: Expected texture width
    ///   - height: Expected texture height
    /// - Returns: CVPixelBuffer in BGRA or RGBAHalf format, or nil if conversion fails
    /// - Throws: Never throws, returns nil on failure
    public static func textureToPixelBuffer(
        _ texture: MTLTexture,
        width: Int,
        height: Int,
        colorSpace: String = "rec709"
    ) -> CVPixelBuffer? {
        // Verify texture properties
        guard texture.width == width && texture.height == height else {
            #if DEBUG
                print("⚠️ Texture size mismatch: \(texture.width)x\(texture.height) vs expected \(width)x\(height)")
            #endif
            return nil
        }

        let pixelFormat = texture.pixelFormat
        let targetFormat: OSType

        if pixelFormat == .rgba16Float {
            targetFormat = kCVPixelFormatType_64RGBAHalf
        } else if pixelFormat == .rgba8Unorm || pixelFormat == .bgra8Unorm || pixelFormat == .bgra8Unorm_srgb {
            targetFormat = kCVPixelFormatType_32BGRA
        } else {
            #if DEBUG
                print("⚠️ Unexpected pixel format: \(pixelFormat)")
            #endif
            return nil
        }

        var pixelBuffer: CVPixelBuffer?
        let options: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferMetalCompatibilityKey: true
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            targetFormat,
            options as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let pixelBuffer = pixelBuffer else {
            #if DEBUG
                print("⚠️ CVPixelBuffer creation failed with status: \(status)")
            #endif
            return nil
        }

        // Explicitly tag color space
        let primaries: CFString
        let transfer: CFString
        let matrix: CFString

        if colorSpace.lowercased() == "srgb" {
            primaries = kCVImageBufferColorPrimaries_ITU_R_709_2
            transfer = "IEC_sRGB" as CFString
            matrix = kCVImageBufferYCbCrMatrix_ITU_R_709_2
        } else {
            primaries = kCVImageBufferColorPrimaries_ITU_R_709_2
            transfer = kCVImageBufferTransferFunction_ITU_R_709_2
            matrix = kCVImageBufferYCbCrMatrix_ITU_R_709_2
        }

        CVBufferSetAttachment(pixelBuffer, kCVImageBufferColorPrimariesKey, primaries, .shouldPropagate)
        CVBufferSetAttachment(pixelBuffer, kCVImageBufferTransferFunctionKey, transfer, .shouldPropagate)
        CVBufferSetAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, matrix, .shouldPropagate)

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            #if DEBUG
                print("⚠️ Could not get pixel buffer base address")
            #endif
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let region = MTLRegionMake2D(0, 0, width, height)

        // Copy texture data to pixel buffer
        texture.getBytes(baseAddress, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)

        return pixelBuffer
    }

    /// Convert a CVPixelBuffer to a Metal texture
    public static func pixelBufferToTexture(
        _ pixelBuffer: CVPixelBuffer,
        device: MTLDevice
    ) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)

        var pixelFormat: MTLPixelFormat = .bgra8Unorm
        if format == kCVPixelFormatType_64RGBAHalf {
            pixelFormat = .rgba16Float
        } else if format == kCVPixelFormatType_32BGRA {
            pixelFormat = .bgra8Unorm
        } else {
            // Fallback or error
            #if DEBUG
                print("⚠️ Unsupported CVPixelBuffer format for texture conversion: \(format)")
            #endif
            return nil
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]

        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let region = MTLRegionMake2D(0, 0, width, height)
            texture.replace(region: region, mipmapLevel: 0, withBytes: baseAddress, bytesPerRow: bytesPerRow)
        }

        return texture
    }
}
