import Foundation

public struct RenderDeviceCatalog: Sendable {
    public init() {}

    public func availableCapabilities() -> [RenderDeviceCapabilities] {
        [MetalRenderDevice.defaultCapabilities]
    }

    public func makeDevice(kind: RenderDeviceKind, engine: MetalSimulationEngine) -> any RenderDevice {
        switch kind {
        case .metalLocal:
            return MetalRenderDevice(engine: engine)
        }
    }
}
