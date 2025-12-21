# Sprint 02 — TDD Plan (Render Devices)

## Tests (write first)

### 1) `RenderDeviceE2ETests.test_export_via_device_catalog()`
- Location: `Tests/MetaVisExportTests/RenderDeviceE2ETests.swift`
- Steps:
  - Build deterministic timeline (procedural generator clip).
  - Instantiate `RenderDeviceCatalog`.
  - Select `MetalRenderDevice`.
  - Export via `VideoExporter` using the device interface.
  - Run `VideoQC` on output.

### Note
- Keep this strictly local-first: the catalog v1 should not attempt any network discovery.

### 2) `RenderDeviceTests.test_catalog_reports_metal_capabilities()`
- Location: `Tests/MetaVisSimulationTests/RenderDeviceTests.swift`
- Assert catalog returns at least one device with expected capability flags.

## Production steps
1. Add `RenderDevice` protocol.
2. Implement `MetalRenderDevice` calling into existing `MetalSimulationEngine.render(...)`.
3. Update exporter path to use `RenderDevice`.

## Definition of done
- Device abstraction introduced with zero behavior regressions.
- E2E tests pass without mocks.
