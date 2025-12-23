# FaceEnhance.metal

## Purpose
Face/beauty enhancement kernels.

## Kernels
- `fx_face_enhance`
  - `source` `texture(0)`
  - `dest` `texture(1)`
  - `faceMask` `texture(2)`
  - `FaceEnhanceParams` `buffer(0)`

- `fx_beauty_enhance`
  - `source` `texture(0)` → `dest` `texture(1)`
  - `BeautyEnhanceParams` `buffer(0)`

## Engine callsites
- PSO prewarm: `Sources/MetaVisSimulation/MetalSimulationEngine.swift`.
