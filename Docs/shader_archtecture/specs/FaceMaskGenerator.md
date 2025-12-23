# FaceMaskGenerator.metal

## Purpose
Generate a face mask texture from a set of normalized face rectangles.

## Kernel
- `fx_generate_face_mask`
  - output mask: `texture(0)`
  - `faceRects` float array: `buffer(0)` (4 floats per rect: x,y,w,h)
  - `faceCount`: `buffer(1)`

## Engine callsites
- Node injection: `Sources/MetaVisSimulation/TimelineCompiler.swift`.
- Parameter packing and special output index: `Sources/MetaVisSimulation/MetalSimulationEngine.swift`.
