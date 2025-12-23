# Bloom.metal

## Purpose
Multi-pass bloom: prefilter/threshold, downsample, upsample+blend, and composite.

## Kernels
- `fx_bloom_prefilter`
  - `source` `texture(0)` → `dest` `texture(1)`
  - `threshold` `buffer(0)`, `knee` `buffer(1)`, `clampMax` `buffer(2)`

- `fx_bloom_downsample`
  - `source` `texture(0)` → `dest` `texture(1)`

- `fx_bloom_upsample_blend`
  - `source` `texture(0)`, `currentMip` `texture(1)` → `dest` `texture(2)`
  - `radius` `buffer(0)`, `weight` `buffer(1)`

- `fx_bloom_threshold`
  - `sourceTexture` `texture(0)` → `destTexture` `texture(1)`
  - `threshold` `buffer(0)`

- `fx_bloom_composite`
  - `sourceTexture` `texture(0)`, `bloomTexture` `texture(1)` → `destTexture` `texture(2)`
  - `BloomCompositeUniforms` `buffer(0)`

## Notes
This file is present and compilable; feature wiring may be added via manifests over time.
