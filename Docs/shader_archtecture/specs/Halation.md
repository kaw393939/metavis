# Halation.metal

## Purpose
Halation effect: threshold/blur/accumulate + composite back onto source.

## Kernels
- `fx_halation_threshold`
  - `sourceTexture` `texture(0)` → `destTexture` `texture(1)`
  - `threshold` `buffer(0)`

- `fx_halation_composite`
  - `sourceTexture` `texture(0)`, `halationTexture` `texture(1)` → `destTexture` `texture(2)`
  - `HalationCompositeUniforms` `buffer(0)`
