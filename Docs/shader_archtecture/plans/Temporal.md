# Plan: Temporal (accumulate/resolve)

Source research: `shader_research/Research_Temporal.md`

## Owners / entry points

- Shader: `Sources/MetaVisGraphics/Resources/Temporal.metal`
- Kernels:
  - `fx_accumulate`
  - `fx_resolve`

## Problem summary (from research)

- Temporal methods require velocity reprojection and history clamping to avoid ghosting.
- Where available, MetalFX temporal scaler may provide a better baseline.

## RenderGraph integration

- Tier: Full
- Fusion group: Standalone
- Perception inputs: optional flow later
- Required graph features: Requires history persistence + motion vectors; hazard-safe read/write.
- Reference: `shader_archtecture/RENDER_GRAPH_INTEGRATION.md` (Temporal)

## Implementation plan

1. **Add motion vectors to the pipeline**
   - Define a velocity buffer/texture source for effects that need it.
2. **History reprojection**
   - Reproject previous frame history using velocity.
   - Sample history with higher-quality reconstruction when needed.
3. **Neighborhood clamp**
   - Clamp reprojected history to min/max of current neighborhood (AABB clamp).
4. **MetalFX evaluation**
   - If the product can accept MetalFX behavior, consider replacing custom temporal with `MTLFXTemporalScaler`.

## Validation

- Visual: moving edges don’t ghost; static regions converge smoothly.
- Correctness: frame-to-frame synchronization is correct (no read/write hazards).

## Sprint mapping

- Primary: `Sprints/24m_render_vs_compute_migrations` (MetalFX adoption + temporal infra)
