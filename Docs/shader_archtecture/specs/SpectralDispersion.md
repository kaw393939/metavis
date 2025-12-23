# SpectralDispersion.metal

## Purpose
Spectral dispersion effect (chromatic separation).

## Kernel
- `cs_spectral_dispersion`
  - `inTexture` `texture(0)` → `outTexture` `texture(1)`
  - `SpectralDispersionParams` `buffer(0)`
