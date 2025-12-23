# Lens.metal

## Purpose
Lens system effects: distortion and chromatic aberration.

## Kernels
- `fx_lens_system`
  - `sourceTexture` `texture(0)` → `destTexture` `texture(1)`
  - `LensSystemParams` `buffer(0)`

- `fx_lens_distortion_brown_conrady`
  - `sourceTexture` `texture(0)` → `destTexture` `texture(1)`
  - `kParams` `buffer(0)` (float2)

- `fx_spectral_ca`
  - `sourceTexture` `texture(0)` → `destTexture` `texture(1)`
  - `intensity` `buffer(0)`
