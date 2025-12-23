# Shader Review: Vignette.metal

**File**: `Sources/MetaVisGraphics/Resources/Vignette.metal`
**Target**: Apple Silicon M3 (Metal 3)

## Status: Cos^4 Law
*   **Analysis**:
    *   Physically correct natural illumination falloff.
*   **M3 Optimization**:
    *   **Bandwidth Waste**: Running a Full-Screen Compute Pass just to darken pixel corners is a massive waste of bandwidth.
    *   **Inline**: This function should be **inlined** into the final Tone Mapping or Color Grading shader.
    *   **Cost**: Doing the math in the final shader costs 0 extra bytes of bandwidth. Doing it here costs Read+Write of full frame.

## Action Plan
- [ ] **Inline**: Move `fx_vignette` logic to `ToneMapping.metal`.
- [ ] **Deprecate**: Remove stand-alone Vignette pass.
