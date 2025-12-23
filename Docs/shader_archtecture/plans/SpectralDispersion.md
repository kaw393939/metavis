# Plan: SpectralDispersion (chromatic aberration)

Source research: `shader_research/Research_SpectralDispersion.md`

## Owners / entry points

- Shader: `Sources/MetaVisGraphics/Resources/SpectralDispersion.metal`
- Kernels:
  - `cs_spectral_dispersion`

## Problem summary (from research)

- True dispersion needs multiple taps; 3-tap RGB is the practical baseline.

## RenderGraph integration

- Tier: Full
- Fusion group: LensSystem
- Perception inputs: none
- Required graph features: Keep taps small; benefit from cache behavior and fusion.
- Reference: `shader_archtecture/RENDER_GRAPH_INTEGRATION.md` (SpectralDispersion)

## Implementation plan

1. **Keep the 3-tap model**
   - Ensure offsets are small and parameterized.
2. **Sampling quality**
   - Evaluate if the look needs higher-quality reconstruction (bicubic approximation).
3. **Fuse with lens system**
   - Prefer integrating into `Lens.metal`’s fused path where feasible.

## Validation

- Visual: CA increases toward edges; no color fringing instability.

## Sprint mapping

- Primary: `Sprints/24l_post_stack_fusion`
