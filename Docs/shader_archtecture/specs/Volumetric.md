# Volumetric.metal

## Purpose
Volumetric lighting effect using depth.

## Kernel
- `fx_volumetric_light`
  - `sourceTexture` `texture(0)`
  - `destTexture` `texture(1)`
  - `depthTexture` `texture(2)`
  - `VolumetricParams` `buffer(0)`
