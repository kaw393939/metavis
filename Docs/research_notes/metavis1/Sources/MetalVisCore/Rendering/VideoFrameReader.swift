import AVFoundation
import Metal
import MetalKit

public final class VideoFrameReader: @unchecked Sendable {
    private let asset: AVAsset
    private let generator: AVAssetImageGenerator
    private var cachedDuration: Double?
    private var cachedMetadata: AssetColorMetadata?

    public init(url: URL) {
        asset = AVAsset(url: url)
        generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
    }

    public func getDuration() async throws -> Double {
        if let duration = cachedDuration {
            return duration
        }
        let duration = try await asset.load(.duration).seconds
        cachedDuration = duration
        return duration
    }

    public func getColorMetadata() async -> AssetColorMetadata {
        if let metadata = cachedMetadata {
            return metadata
        }

        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else { return .rec709 }

            let formatDescriptions = try await track.load(.formatDescriptions)
            guard let formatDesc = formatDescriptions.first else { return .rec709 }

            // Extract Color Primaries
            var colorSpace: AssetColorMetadata.ColorSpace = .rec709
            if let primaries = CMFormatDescriptionGetExtension(formatDesc, extensionKey: kCVImageBufferColorPrimariesKey) as? String {
                if primaries == (kCVImageBufferColorPrimaries_ITU_R_2020 as String) {
                    colorSpace = .rec2020
                } else if primaries == (kCVImageBufferColorPrimaries_P3_D65 as String) {
                    colorSpace = .p3
                }
            }

            // Extract Transfer Function
            var transfer: AssetColorMetadata.TransferFunction = .rec709
            if let tf = CMFormatDescriptionGetExtension(formatDesc, extensionKey: kCVImageBufferTransferFunctionKey) as? String {
                if tf == (kCVImageBufferTransferFunction_Linear as String) {
                    transfer = .linear
                } else if tf == (kCVImageBufferTransferFunction_ITU_R_709_2 as String) {
                    transfer = .rec709
                } else if tf == (kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String) {
                    transfer = .pq
                } else if tf == (kCVImageBufferTransferFunction_ITU_R_2100_HLG as String) {
                    transfer = .hlg
                } else if tf == "com.apple.log" {
                    transfer = .appleLog
                }
            }

            let metadata = AssetColorMetadata(colorSpace: colorSpace, transferFunction: transfer)
            cachedMetadata = metadata
            return metadata

        } catch {
            print("Failed to load video metadata: \(error)")
            return .rec709
        }
    }

    public func getTexture(at time: Double, device: MTLDevice, textureLoader _: MTKTextureLoader) async throws -> MTLTexture {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        do {
            let (cgImage, _) = try await generator.image(at: cmTime)
            // print("Got frame at \(time) (actual: \(actualTime.seconds)) bpc=\(cgImage.bitsPerComponent) bpp=\(cgImage.bitsPerPixel) alpha=\(cgImage.alphaInfo.rawValue) w=\(cgImage.width) h=\(cgImage.height)")

            // Use robust manual loading to ensure RGBA format and avoid BGRA/RGBA swizzle issues
            return try createTextureRobust(cgImage: cgImage, device: device)
        } catch {
            print("VideoFrameReader Error: Failed to generate image at \(time): \(error)")
            throw error
        }
    }

    private func createTextureRobust(cgImage: CGImage, device: MTLDevice) throws -> MTLTexture {
        let width = cgImage.width
        let height = cgImage.height

        // Preserve original color space
        let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()

        // Check for high bit-depth (HDR/10-bit sources often come as 16-bit CGImages)
        let isHighPrecision = cgImage.bitsPerComponent > 8

        let targetBPC = isHighPrecision ? 16 : 8

        // Setup Bitmap Info
        // 8-bit: Big Endian (RGBA)
        // 16-bit: Little Endian (RGBA) - Common for 16-bit buffers on Apple Silicon
        let bitmapInfo: UInt32
        if isHighPrecision {
            bitmapInfo = CGBitmapInfo.byteOrder16Little.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        } else {
            bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: targetBPC,
            bytesPerRow: 0, // Auto calculate
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw NSError(domain: "VideoFrameReader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create bitmap context"])
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else {
            throw NSError(domain: "VideoFrameReader", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to get context data"])
        }

        // Select appropriate Metal Pixel Format
        let pixelFormat: MTLPixelFormat = isHighPrecision ? .rgba16Unorm : .rgba8Unorm

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw NSError(domain: "VideoFrameReader", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to create Metal texture"])
        }

        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: data,
            bytesPerRow: context.bytesPerRow
        )

        return texture
    }

    private func createTextureFallback(cgImage: CGImage, device: MTLDevice) throws -> MTLTexture {
        let width = cgImage.width
        let height = cgImage.height

        // Use sRGB explicitly to ensure consistent color space
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        // BGRA 8-bit (using noneSkipFirst to ignore alpha and just treat as BGRX)
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw NSError(domain: "VideoFrameReader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create fallback context"])
        }

        // Clear context to ensure no artifacts
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))

        // Draw the image - Core Graphics handles color space conversion here
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let newCGImage = context.makeImage() else {
            throw NSError(domain: "VideoFrameReader", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to create fallback image"])
        }

        // print("Fallback created image: \(width)x\(height) bpc=\(newCGImage.bitsPerComponent) bpp=\(newCGImage.bitsPerPixel) alpha=\(newCGImage.alphaInfo.rawValue) space=\(String(describing: newCGImage.colorSpace?.name))")

        let loader = MTKTextureLoader(device: device)
        // Use synchronous load for fallback to ensure we have it
        return try loader.newTexture(cgImage: newCGImage, options: [.SRGB: false])
    }
}
