# MaskedBlur.metal

## Purpose
Apply blur selectively based on a mask.

## Kernel
- `fx_masked_blur`
  - `inputTexture` `texture(0)`
  - `maskTexture` `texture(1)`
  - `outputTexture` `texture(2)`
  - `blurRadius` `buffer(0)`
  - `maskThreshold` `buffer(1)`
