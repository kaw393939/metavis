# Plan: ZonePlate (test signal)

Source research: `shader_research/Research_ZonePlate.md`

## Owners / entry points

- Shader: `Sources/MetaVisGraphics/Resources/ZonePlate.metal`
- Kernels:
  - `fx_zone_plate`

## Problem summary (from research)

- This is a precision test chart; avoid “optimizations” that change the signal.

## RenderGraph integration

- Tier: Full
- Fusion group: Standalone (debug)
- Perception inputs: none
- Required graph features: Debug pattern; keep isolated.
- Reference: `shader_archtecture/RENDER_GRAPH_INTEGRATION.md` (ZonePlate)

## Implementation plan

1. **Preserve precision**
   - Keep float math and stable center sampling (`gid + 0.5`) where applicable.
2. **Document intent**
   - The zone plate should alias if the pipeline is wrong; that’s part of the diagnostic value.

## Validation

- Visual: chart matches expected frequency sweep and symmetry.

## Sprint mapping

- Primary: `Sprints/24k_aces13_color_pipeline` (diagnostic correctness suite)
