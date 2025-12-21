# Implemented Features

## Status: Implemented

## Acceptance criteria (met)
- ✅ A `RenderDevice` protocol exists (capabilities + render API).
- ✅ A `MetalRenderDevice` adapter wraps `MetalSimulationEngine`.
- ✅ `VideoExporter` can render via a device interface (defaults to Metal).
- ✅ E2E export via device passes QC.

## Accomplishments
- **RenderDevice Protocol**: Implemented as interface for rendering backends.
- **MetalRenderDevice**: Concrete implementation wrapping `MetalSimulationEngine`.
- **RenderDeviceCatalog**: Factory for creating devices.
- **Device Selection Logic**: Added `bestCapabilities(for:watermark:)` and `makeBestDevice(...)` to select a compatible device for a `QualityProfile`.
- **Test Coverage**: `Tests/MetaVisSimulationTests/RenderDeviceTests.swift` includes selection behavior.

## Tests
- `Tests/MetaVisSimulationTests/RenderDeviceTests.swift`
- `Tests/MetaVisExportTests/RenderDeviceE2ETests.swift`
