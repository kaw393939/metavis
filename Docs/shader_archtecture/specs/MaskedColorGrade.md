# MaskedColorGrade.metal

## Purpose
Apply a color grade selectively using a segmentation/mask texture.

## Kernel
- `fx_masked_grade`
  - `source` `texture(0)`
  - `dest` `texture(1)`
  - `maskParams` `texture(2)`
  - `MaskedColorGradeParams` `buffer(0)`
