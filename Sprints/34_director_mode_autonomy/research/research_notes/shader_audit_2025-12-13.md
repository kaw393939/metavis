# Graphics Audit: ACEScg Compliance & Shader Improvements

Date: 2025-12-13  
Scope: `Sources/MetaVisGraphics/Resources/*.metal`

## Summary
The pipeline is foundational but incomplete for strict ACES 1.3-style color management.

## Key findings (mapped to repo)

### Working space
- `Sources/MetaVisGraphics/Resources/ColorSpace.metal` defines `MAT_Rec709_to_ACEScg` and `MAT_ACEScg_to_Rec709` as `constant float3x3` (good).
- `Sources/MetaVisSimulation/TimelineCompiler.swift` currently hard-wires `idt_rec709_to_acescg` for all sources and ends the graph with `odt_acescg_to_rec709`.

### IDT coverage
- Only `idt_rec709_to_acescg` exists today. No Rec.2020 or log-camera IDTs.

### ODT coverage
- SDR path used by the timeline compiler is `odt_acescg_to_rec709` (simple matrix + gamma + clamp).
- `Sources/MetaVisGraphics/Resources/ACES.metal` contains an RRT-style fit (`ACEScg_to_Rec709_SDR`) but it is not the compiler’s current exit-gate.
- HDR path (`ACEScg_to_Rec2020_PQ`) exists but uses a simplified tone mapper.

### Grading
- LUT path (`fx_apply_lut`) converts ACEScg → ACEScct → LUT → ACEScg (good).
- `fx_color_grade_simple` applies exposure/contrast/sat/temp/tint directly in whatever space the texture is in; risky if that texture is linear ACEScg.

### Volumetrics
- `fx_volumetric_light` samples `sourceTexture` directly and accumulates in screen space; correctness depends on whether the effect runs pre-ODT (ACEScg) or post-ODT (display-referred).

## Recommendations

### High priority
1. Add additional IDTs (Rec.2020, log formats) and a way for assets/clips to declare input color encoding.
2. Consolidate the “display exit gate”: decide whether Timeline uses the simple ODT kernel or a filmic RRT+ODT-fit kernel, then make it the single canonical output transform.
3. Deprecate or replace `fx_color_grade_simple` with an ACEScct- or CDL-based grade.
4. Add an out-of-gamut visualization shader (ACEScg → Rec.709) for governance/QC.

### Follow-ups
- Verify where `fx_volumetric_light` sits relative to ODT in the render graph before trusting its lighting assumptions.
- Standardize shader kernel naming conventions (without breaking existing feature manifests).
