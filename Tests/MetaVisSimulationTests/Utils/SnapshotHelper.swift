import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// Helper to manage Golden EXR images for Snapshot Testing.
final class SnapshotHelper {
    
    enum Error: Swift.Error {
        case destinationCreationFailed
        case sourceCreationFailed
        case finalizationFailed
        case dataProviderFailed
    }
    
    let storageURL: URL
    
    init() {
        // Store snapshots in a dedicated directory in the project root/Tests/Snapshots
        let fileURL = URL(fileURLWithPath: #file) // This file
        let projectRoot = fileURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        self.storageURL = projectRoot.appendingPathComponent("Snapshots")
        
        try? FileManager.default.createDirectory(at: self.storageURL, withIntermediateDirectories: true)
    }

    static var shouldRecordGoldens: Bool {
        ProcessInfo.processInfo.environment["RECORD_GOLDENS"] == "1"
    }
    
    /// Writes a Float32 RGBA buffer to an EXR file.
    func saveGolden(name: String, buffer: [Float], width: Int, height: Int) throws -> URL {
        let url = storageURL.appendingPathComponent("\(name).exr")

        // Ensure recording/updating is deterministic by overwriting any existing file.
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        
        // Create Data Provider from Float Buffer
        let byteCount = buffer.count * MemoryLayout<Float>.size
        let data = Data(bytes: buffer, count: byteCount)
        
        guard let provider = CGDataProvider(data: data as CFData) else {
            throw Error.dataProviderFailed
        }
        
        // Create CGImage (Assume RGBA Float32 Linear)
        // 128 bpp = 32 bits * 4 components
        let bitmapInfo = CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGBitmapInfo.floatComponents.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 32,
            bitsPerPixel: 128,
            bytesPerRow: width * 16, // 4 floats * 4 bytes
            space: CGColorSpace(name: CGColorSpace.linearSRGB)!, // Approximate correct container space for EXR
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            throw Error.sourceCreationFailed
        }
        
        // Write to EXR
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "com.ilm.openexr-image" as CFString, 1, nil) else {
            throw Error.destinationCreationFailed
        }
        
        CGImageDestinationAddImage(dest, cgImage, nil)
        
        guard CGImageDestinationFinalize(dest) else {
            throw Error.finalizationFailed
        }
        
        print("Saved Golden Image: \(url.path)")
        return url
    }
    
    /// Loads an EXR file into a Float32 buffer.
    func loadGolden(name: String) throws -> [Float]? {
        let url = storageURL.appendingPathComponent("\(name).exr")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        
        let width = cgImage.width
        let height = cgImage.height
        let pixelCount = width * height
        var buffer = [Float](repeating: 0, count: pixelCount * 4)
        
        let colorSpace = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let bitmapInfo = CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGBitmapInfo.floatComponents.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
        
        let context = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 32,
            bytesPerRow: width * 16,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        )
        
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        return buffer
    }
}
