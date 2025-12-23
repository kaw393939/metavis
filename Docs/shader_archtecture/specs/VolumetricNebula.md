# VolumetricNebula.metal

## Purpose
Procedural volumetric nebula raymarch + composite.

## Kernels
- `fx_volumetric_nebula`
  - `depthTexture` `texture(0)`
  - `outputTexture` `texture(1)`
  - `VolumetricNebulaParams` `buffer(0)`
  - `GradientStop3D*` `buffer(1)`
  - `gradientCount` `buffer(2)`

- `fx_volumetric_composite`
  - `sceneTexture` `texture(0)`
  - `volumetricTexture` `texture(1)`
  - `outputTexture` `texture(2)`

## Engine callsites
- Special-case bindings and output indices are encoded in `Sources/MetaVisSimulation/MetalSimulationEngine.swift`.

## Performance notes (M3+)
- This is a likely hotspot (raymarch loop + noise); profile step count and branch coherence.
- Consider specialized “quality tiers” via function constants to reduce dynamic branching.
