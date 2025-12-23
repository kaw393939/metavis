# ClearColor.metal

## Purpose
Deterministic clear/fill kernel for empty timelines and tests.

## Kernels
- `clear_color`
  - Output: `output` `texture(1)`

## Engine callsites
- Empty timeline root node: `Sources/MetaVisSimulation/TimelineCompiler.swift`.
- PSO prewarm: `Sources/MetaVisSimulation/MetalSimulationEngine.swift`.
