# Plan: Macbeth (color chart)

Source research: `shader_research/Research_Macbeth.md`

## Owners / entry points

- Shader: `Sources/MetaVisGraphics/Resources/Macbeth.metal`
- Kernels:
  - `fx_macbeth`

## Problem summary (from research)

- Macbeth patch values should be correct in ACEScg linear.

## RenderGraph integration

- Tier: Full
- Fusion group: Standalone (debug)
- Perception inputs: none
- Required graph features: Debug chart; keep isolated.
- Reference: `shader_archtecture/RENDER_GRAPH_INTEGRATION.md` (Macbeth)

## Implementation plan

1. **Replace/verify patch constants**
   - Store `float3[24]` in `constant` address space.
   - Verify against a documented reference dataset (ACEScg).
2. **Grid logic**
   - Keep mapping from UV → patch index straightforward and deterministic.

## Validation

- Numeric: sample patch centers and verify values.

## Sprint mapping

- Primary: `Sprints/24k_aces13_color_pipeline` (reference correctness tools)
