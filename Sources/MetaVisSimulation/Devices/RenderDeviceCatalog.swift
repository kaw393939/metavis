import Foundation
import MetaVisCore

public enum RenderDeviceSelectionError: Error, LocalizedError, Sendable, Equatable {
    case noCompatibleDevice(requiredResolutionHeight: Int, requiresWatermark: Bool)

    public var errorDescription: String? {
        switch self {
        case .noCompatibleDevice(let h, let requiresWatermark):
            return "No compatible render device (resolutionHeight=\(h), requiresWatermark=\(requiresWatermark))"
        }
    }
}

public struct RenderDeviceCatalog: Sendable {
    public init() {}

    public func availableCapabilities() -> [RenderDeviceCapabilities] {
        [MetalRenderDevice.defaultCapabilities]
    }

    /// Returns the best available device capabilities that can satisfy the requested quality.
    ///
    /// Current heuristic: pick the highest-capability compatible device.
    public func bestCapabilities(for quality: QualityProfile, watermark: WatermarkSpec? = nil) -> RenderDeviceCapabilities? {
        let requiresWatermark = (watermark != nil)
        let requiredHeight = quality.resolutionHeight

        return availableCapabilities()
            .filter { caps in
                caps.maxResolutionHeight >= requiredHeight && (!requiresWatermark || caps.supportsWatermark)
            }
            .sorted { a, b in
                if a.maxResolutionHeight != b.maxResolutionHeight { return a.maxResolutionHeight > b.maxResolutionHeight }
                return a.supportsWatermark && !b.supportsWatermark
            }
            .first
    }

    public func makeBestDevice(
        for quality: QualityProfile,
        engine: MetalSimulationEngine,
        watermark: WatermarkSpec? = nil
    ) throws -> any RenderDevice {
        guard let caps = bestCapabilities(for: quality, watermark: watermark) else {
            throw RenderDeviceSelectionError.noCompatibleDevice(
                requiredResolutionHeight: quality.resolutionHeight,
                requiresWatermark: watermark != nil
            )
        }
        return makeDevice(kind: caps.kind, engine: engine)
    }

    public func makeDevice(kind: RenderDeviceKind, engine: MetalSimulationEngine) -> any RenderDevice {
        switch kind {
        case .metalLocal:
            return MetalRenderDevice(engine: engine)
        }
    }
}
