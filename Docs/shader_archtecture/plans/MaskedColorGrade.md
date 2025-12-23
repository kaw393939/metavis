# Plan: MaskedColorGrade (selective color)

Source research: `shader_research/Research_MaskedColorGrade.md`

## Owners / entry points

- Shader: `Sources/MetaVisGraphics/Resources/MaskedColorGrade.metal`
- Kernels:
  - `fx_masked_grade`

## Problem summary (from research)

- Current “selective color” math can be branchy (HSV/HSL conversions), causing SIMD divergence.

## Target architecture fit

- Use branchless keying math; blend graded vs original via `mix` with mask alpha.

## RenderGraph integration

- Tier: Full
- Fusion group: FinalColor (if part of final look) or Standalone
- Perception inputs: mask texture (often perception-derived)
- Required graph features: Stable key math; mask may be perception-provided.
- Reference: `shader_archtecture/RENDER_GRAPH_INTEGRATION.md` (MaskedColorGrade)

## Implementation plan

1. **Replace hue-selection math** with a branchless model.
   - Prefer HCV (Hue–Chroma–Value) style computations, or a perceptual-ish chroma-plane distance.
   - Avoid `if`/`else` for hue wrap; handle wrap via modular arithmetic.
2. **Define a stable “distance” metric**
   - Compute a chroma-plane distance to the target key; convert to a smooth mask via `smoothstep`.
3. **Blend model**
   - `out = mix(in, graded, keyMask * userMaskAlpha)`.
4. **Numerical stability**
   - Guard degenerate chroma cases branchlessly (tiny epsilon).

## Validation

- Visual: hue key is stable near reds (wrap boundary) and at low saturation.
- Performance: kernel stays branchless in the hot path.

## Sprint mapping

- Primary: `Sprints/24l_post_stack_fusion`
