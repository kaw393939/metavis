# ToneMapping.metal

## Purpose
Tone mapping kernels.

## Kernels
- `fx_tonemap_aces`
  - `sourceTexture` `texture(0)` → `destTexture` `texture(1)`
  - `exposure` `buffer(0)`

- `fx_tonemap_pq`
  - `sourceTexture` `texture(0)` → `destTexture` `texture(1)`
  - `maxNits` `buffer(0)`
