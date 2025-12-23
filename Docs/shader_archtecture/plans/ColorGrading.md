# Plan: ColorGrading (from Research_ColorGrading.md)

## Shipping touchpoints
- Research: `shader_research/Research_ColorGrading.md`
- Shader: `Sources/MetaVisGraphics/Resources/ColorGrading.metal` (`fx_apply_lut`, `fx_color_grade_simple`, `fx_false_color_turbo`)
- Engine binds LUT as `texture(2)` when provided.

## Issues identified in research
- Trilinear LUT sampling is fast; tetrahedral is higher quality but more ALU.
- Log shaper math in shader is wasteful; should be precomputed.

## RenderGraph integration

- Tier: Full
- Fusion group: FinalColor
- Perception inputs: none
- Required graph features: LUT sampling ideally fused with tonemap/ODT.
- Reference: `shader_archtecture/RENDER_GRAPH_INTEGRATION.md` (ColorGrading)

## Holistic solution (fits 24k/24l)
- Two-tier quality strategy:
  - realtime preview: hardware trilinear
  - offline/export: tetrahedral
- Move expensive log shaping into a 1D shaper LUT.

## Concrete changes
- Keep default path as hardware trilinear 3D sampling.
- Add an optional tetrahedral interpolation path (gated by quality profile / export).
- Add a 1D shaper LUT option:
  - precompute in Swift
  - bind as a 1D/2D texture (implementation choice) to avoid `log/exp` per pixel

## Validation
- Visual tests for diagonal ramps and saturated gradients.
- Ensure LUT indexing is stable and matches expected LUT cube conventions.

## Dependencies
- Sprint 24k (color pipeline), optionally 24l if fused into a post stack.
