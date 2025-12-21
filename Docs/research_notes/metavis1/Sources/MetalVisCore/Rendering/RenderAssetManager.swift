import Foundation
import Metal
import MetalKit
import Shared

public struct AssetColorMetadata: Sendable {
    public enum ColorSpace: Int, Sendable {
        case sRGB = 0
        case rec709 = 1
        case rec2020 = 2
        case p3 = 3
    }

    public enum TransferFunction: Int, Sendable {
        case linear = 0
        case sRGB = 1
        case rec709 = 2
        case pq = 3
        case hlg = 4
        case appleLog = 5
    }

    public var colorSpace: ColorSpace
    public var transferFunction: TransferFunction

    public static let sRGB = AssetColorMetadata(colorSpace: .sRGB, transferFunction: .sRGB)
    public static let rec709 = AssetColorMetadata(colorSpace: .rec709, transferFunction: .rec709)
    public static let linearSRGB = AssetColorMetadata(colorSpace: .sRGB, transferFunction: .linear)
}

public struct SendableTexture: @unchecked Sendable {
    public let texture: MTLTexture
    public let colorMetadata: AssetColorMetadata

    public init(_ texture: MTLTexture, metadata: AssetColorMetadata = .sRGB) {
        self.texture = texture
        colorMetadata = metadata
    }
}

public actor RenderAssetManager {
    private let device: MTLDevice
    private var imageCache: [String: SendableTexture] = [:]
    private var videoCache: [String: VideoFrameReader] = [:]

    public init(device: MTLDevice) {
        self.device = device
    }

    public func loadTexture(from path: String) throws -> SendableTexture {
        if let cached = imageCache[path] {
            return cached
        }

        let url = URL(fileURLWithPath: path)
        // Use MTKTextureLoader directly for simplicity and robustness
        let loader = MTKTextureLoader(device: device)
        // We assume images are sRGB for now unless we inspect them deeper
        let texture = try loader.newTexture(URL: url, options: [
            .SRGB: true, // This tells Metal to treat data as sRGB. Sampling will linearize it.
            .origin: MTKTextureLoader.Origin.topLeft
        ])

        // Since .SRGB is true, the texture is sRGB encoded, but sampling returns Linear sRGB.
        // However, our pipeline expects to handle conversion manually in some cases?
        // Wait, if we use .SRGB: true, the shader reads Linear values (hardware conversion).
        // So the transfer function effectively becomes "Linear" from the shader's perspective.
        // But the primaries are still sRGB.
        let metadata = AssetColorMetadata(colorSpace: .sRGB, transferFunction: .linear)

        let sendable = SendableTexture(texture, metadata: metadata)
        imageCache[path] = sendable
        return sendable
    }

    public func getVideoReader(for path: String) -> VideoFrameReader {
        if let cached = videoCache[path] {
            return cached
        }

        let url = URL(fileURLWithPath: path)
        let reader = VideoFrameReader(url: url)
        videoCache[path] = reader
        return reader
    }

    public func clearCache() {
        imageCache.removeAll()
        videoCache.removeAll()
    }
}
