# Awaiting Implementation

## Status
- ✅ Sprint is complete (local render devices + selection).

## Gaps & Missing Features
- (Resolved) **Device Selection Logic**: `RenderDeviceCatalog.bestCapabilities(for:watermark:)` and `makeBestDevice(...)` choose a compatible device.
- **Remote Support**: Out of scope for v1; no infrastructure for remote execution.

## Technical Debt
- **Hardcoded Catalog**: `RenderDeviceCatalog` just creates `MetalRenderDevice` directly in `makeDevice` switch.

## Recommendations
- If/when remote devices exist: implement a capability scorer and add remote device kinds.

