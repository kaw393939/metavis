# FilmGrain.metal

## Purpose
Add procedural film grain.

## Kernel
- `fx_film_grain`
  - `sourceTexture` `texture(0)` → `destTexture` `texture(1)`
  - `FilmGrainUniforms` `buffer(0)`
