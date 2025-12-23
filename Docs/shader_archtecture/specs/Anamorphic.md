# Anamorphic.metal

## Purpose
Anamorphic-style streak thresholding and composite.

## Kernels
- `fx_anamorphic_threshold`
  - Inputs: `sourceTexture` `texture(0)`
  - Output: `destTexture` `texture(1)`
  - Params: `threshold` `buffer(0)`

- `fx_anamorphic_composite`
  - Inputs: `sourceTexture` `texture(0)`, `streakTexture` `texture(1)`
  - Output: `destTexture` `texture(2)`
  - Params: `AnamorphicCompositeUniforms` `buffer(0)`

## Engine bindings
Matches the general multi-input convention documented in `BINDINGS.md`.
