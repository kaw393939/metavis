# Sprint 2 Audit: Render Devices

## Status: Implemented

## Verified implementation
- `RenderDevice` protocol exists with `RenderDeviceCapabilities`.
- `MetalRenderDevice` wraps `MetalSimulationEngine`.
- `RenderDeviceCatalog` supports capability reporting and selection:
	- `availableCapabilities()`
	- `bestCapabilities(for:watermark:)`
	- `makeBestDevice(for:engine:watermark:)`
- `VideoExporter` supports device-based export via `init(device:)` (default remains local Metal).

## Tests
- `Tests/MetaVisSimulationTests/RenderDeviceTests.swift`
- `Tests/MetaVisExportTests/RenderDeviceE2ETests.swift`

## Notes / future work (out of scope for v1)
- Remote/LAN render devices and discovery.
- Catalog remains hardcoded to local Metal until additional device kinds exist.
