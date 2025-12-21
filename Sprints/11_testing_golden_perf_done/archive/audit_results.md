# Sprint 11 Audit: Testing Golden Frames + Performance Budgets

## Status: Fully Implemented

## Accomplishments
- **Golden Frame Harness**: Implemented `GoldenFrameHashTests` using `FrameHashing` (SHA256 of downsampled 64x64 pixels).
- **Performance Budgets**: Implemented `RenderPerfTests` with configurable budgets for frame rendering.
- **Export Perf Budgets**: Implemented `ExportPerfTests` to enforce an export time budget and assert no CPU readback.
- **Memory Perf Budgets**: Implemented `RenderMemoryPerfTests` to enforce a peak RSS delta budget (env-tunable).
- **Allocation Guardrails**: `RenderAllocationTests` verifies zero steady-state texture allocations during multi-pass rendering using `MetalSimulationDiagnostics`.
- **Stability**: Downsampling pixels before hashing ensures tests are stable across different GPU architectures and driver versions.

## Gaps & Missing Features
- None identified for this sprint scope.

## Performance Optimizations
- **Texture Pooling**: Verified by `RenderAllocationTests`, ensuring the engine reuses textures efficiently.
- **Downsampled Hashing**: Minimizes CPU time spent hashing large buffers in tests.

## Low Hanging Fruit
- Tighten performance budgets as the engine stabilizes.
- Tighten budgets via env vars in CI when ready.
