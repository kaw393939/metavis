# Watermark.metal

## Purpose
Render watermark overlays for export.

## Kernel
- `watermark_diagonal_stripes`
  - `image` `texture(0)` (read/write, `half`)
  - `WatermarkUniforms` `buffer(0)`

## Engine callsites
- PSO prewarm: `Sources/MetaVisSimulation/MetalSimulationEngine.swift`.
