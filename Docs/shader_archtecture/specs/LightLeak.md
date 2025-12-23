# LightLeak.metal

## Purpose
Procedural light leak overlay.

## Kernel
- `cs_light_leak`
  - `inTexture` `texture(0)` → `outTexture` `texture(1)`
  - `LightLeakParams` `buffer(0)`
