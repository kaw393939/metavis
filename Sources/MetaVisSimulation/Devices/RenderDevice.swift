import Foundation
import CoreVideo
import MetaVisCore

public enum RenderDeviceKind: String, Codable, Sendable {
    case metalLocal
}

public struct RenderDeviceCapabilities: Codable, Sendable, Equatable {
    public var kind: RenderDeviceKind
    public var name: String
    public var maxResolutionHeight: Int
    public var supportsWatermark: Bool

    public init(
        kind: RenderDeviceKind,
        name: String,
        maxResolutionHeight: Int,
        supportsWatermark: Bool
    ) {
        self.kind = kind
        self.name = name
        self.maxResolutionHeight = maxResolutionHeight
        self.supportsWatermark = supportsWatermark
    }
}

public protocol RenderDevice: Sendable {
    var capabilities: RenderDeviceCapabilities { get }

    func configure() async throws

    func render(
        request: RenderRequest,
        to cvPixelBuffer: CVPixelBuffer,
        watermark: WatermarkSpec?
    ) async throws
}
