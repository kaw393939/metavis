# Temporal.metal

## Purpose
Temporal accumulation/resolution kernels.

## Kernels
- `fx_accumulate`
  - `sourceTexture` `texture(0)`
  - `accumTexture` `texture(1)` (read/write)
  - `weight` `buffer(0)`

- `fx_resolve`
  - `accumTexture` `texture(0)` → `destTexture` `texture(1)`
