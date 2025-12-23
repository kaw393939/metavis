# ColorGrading.metal

## Purpose
Color grading and visualization in ACEScg working space.

## Kernels
- `fx_apply_lut`
  - `sourceTexture` `texture(0)`
  - `destTexture` `texture(1)`
  - `lutTexture` `texture(2)` (3D LUT)
  - `intensity` `buffer(0)`

- `fx_color_grade_simple`
  - `sourceTexture` `texture(0)` → `destTexture` `texture(1)`
  - `ColorGradeParams` `buffer(0)`

- `fx_false_color_turbo`
  - `sourceTexture` `texture(0)` → `destTexture` `texture(1)`
  - `FalseColorParams` `buffer(0)`

## Engine callsites
- Feature manifests: `Sources/MetaVisSimulation/Features/StandardFeatures.swift`.
- Parameter packing: `Sources/MetaVisSimulation/MetalSimulationEngine.swift` (struct must match Metal layout/padding).
