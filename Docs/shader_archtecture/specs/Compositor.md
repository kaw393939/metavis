# Compositor.metal

## Purpose
Multi-clip compositing and transitions.

## Kernels
- `compositor_alpha_blend`
  - `layer1` `texture(0)`
  - `layer2` `texture(1)`
  - output `texture(2)`
  - `alpha1` `buffer(0)`, `alpha2` `buffer(1)`

- `compositor_multi_layer`
  - `layers` `texture(0)` (2D array)
  - output `texture(1)`
  - `alphas` `buffer(0)`, `layerCount` `buffer(1)`

- `compositor_crossfade`
  - `clipA` `texture(0)`, `clipB` `texture(1)` → output `texture(2)`
  - `t` `buffer(0)`

- `compositor_dip`
  - `clipA` `texture(0)`, `clipB` `texture(1)` → output `texture(2)`
  - `p` `buffer(0)`, `dipColor` `buffer(1)`

- `compositor_wipe`
  - `clipA` `texture(0)`, `clipB` `texture(1)` → output `texture(2)`
  - `p` `buffer(0)`, `direction` `buffer(1)`

## Engine callsites
- Graph creation: `Sources/MetaVisSimulation/TimelineCompiler.swift`.
- Binding rules: `Sources/MetaVisSimulation/MetalSimulationEngine.swift`.
