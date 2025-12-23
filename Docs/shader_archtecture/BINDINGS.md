# Runtime binding conventions (as implemented)

This file documents the bindings **as they exist today** in `Sources/MetaVisSimulation/MetalSimulationEngine.swift`.

## 1) Texture binding rules

### 1.1 Default single-input kernels
- Primary input: `texture(0)` (key: `input` or `source`)
- Primary output: `texture(1)`

### 1.2 Compositor kernels (`Compositor.metal`)
- `compositor_crossfade`, `compositor_dip`, `compositor_wipe`
  - `clipA`: `texture(0)`
  - `clipB`: `texture(1)`
  - output: `texture(2)`

- `compositor_alpha_blend`
  - `layer1`: `texture(0)`
  - `layer2`: `texture(1)`
  - output: `texture(2)`

### 1.3 VolumetricNebula
- `fx_volumetric_nebula`
  - `depth`: `texture(0)`
  - output: `texture(1)`

- `fx_volumetric_composite`
  - `scene`: `texture(0)`
  - `volumetric`: `texture(1)`
  - output: `texture(2)`

### 1.4 Face mask generation
- `fx_generate_face_mask`
  - output: `texture(0)`

### 1.5 Extra named inputs

When a node has additional named inputs, the engine binds them **after** the primary input/output:
- For most kernels: start at `texture(2)`.
- For compositor kernels: start at `texture(3)` (since they already occupy 0/1/2).

Extra inputs are bound in a stable order:
1. `mask` / `faceMask`
2. All other keys (lexicographically)

### 1.6 Exceptions (explicit)
- `fx_masked_blur` (`MaskedBlur.metal`)
  - input: `texture(0)`
  - mask: `texture(1)`
  - output: `texture(2)`
  - params: `radius` → `buffer(0)`, `threshold` → `buffer(1)`

## 2) Buffer binding rules

### 2.1 Default
- Most kernels use `buffer(0)` for a single uniform struct or scalar.

### 2.2 Examples currently encoded in the engine
- `fx_blur_h`, `fx_blur_v`: `radius` in `buffer(0)`
- `fx_tonemap_aces`: `exposure` in `buffer(0)`
- `fx_tonemap_pq`: `maxNits` in `buffer(0)`
- `fx_color_grade_simple`: `ColorGradeParams` in `buffer(0)`
- `compositor_alpha_blend`: `alpha1` in `buffer(0)`, `alpha2` in `buffer(1)`
- `compositor_dip`: `progress` in `buffer(0)`, `dipColor` packed (float4) in `buffer(1)`
- `compositor_wipe`: `progress` in `buffer(0)`, `direction` in `buffer(1)`

## 3) Working textures and formats

The engine generally allocates outputs as:
- `pixelFormat`: `.rgba16Float`
- `usage`: `[.shaderRead, .shaderWrite]`
- `storageMode`: `.private`
