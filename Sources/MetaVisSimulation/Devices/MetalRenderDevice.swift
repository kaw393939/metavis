import Foundation
import CoreVideo
import MetaVisCore

public actor MetalRenderDevice: RenderDevice {
    public static let defaultCapabilities = RenderDeviceCapabilities(
        kind: .metalLocal,
        name: "Metal (Local)",
        maxResolutionHeight: 4320,
        supportsWatermark: true
    )

    public nonisolated let capabilities: RenderDeviceCapabilities = MetalRenderDevice.defaultCapabilities

    private let engine: MetalSimulationEngine

    public init(engine: MetalSimulationEngine) {
        self.engine = engine
    }

    public func configure() async throws {
        try await engine.configure()
    }

    public func render(
        request: RenderRequest,
        to cvPixelBuffer: CVPixelBuffer,
        watermark: WatermarkSpec?
    ) async throws {
        try await engine.render(request: request, to: cvPixelBuffer, watermark: watermark)
    }
}
