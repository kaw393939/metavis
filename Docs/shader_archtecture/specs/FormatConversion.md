# FormatConversion.metal

## Purpose
Format and channel conversion kernels.

## Kernel
- `rgba_to_bgra`
  - `source` `texture(0)` (read)
  - `dest` `texture(1)` (write)

- `resize_bilinear_rgba16f`
  - `source` `texture(0)` (sample)
  - `dest` `texture(1)` (write)
