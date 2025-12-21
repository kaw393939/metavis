# Implemented Features

## Status: Fully Implemented

## Accomplishments
- **Golden Tests**: Uses `FrameHashing` to assert deterministic output.
- **Performance Budgets**: `RenderPerfTests` implements budget checks.
- **Export Perf**: `ExportPerfTests` enforces export time budget + asserts no CPU readback.
- **Memory Perf**: `RenderMemoryPerfTests` asserts a peak RSS delta budget (env-tunable).
- **Zero-alloc checks**: `RenderAllocationTests` verifies pool usage.
