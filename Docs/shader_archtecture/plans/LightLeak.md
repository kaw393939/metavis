# Plan: LightLeak (procedural overlay)

Source research: `shader_research/Research_LightLeak.md`

## Owners / entry points

- Shader: `Sources/MetaVisGraphics/Resources/LightLeak.metal`
- Kernels:
  - `cs_light_leak`

## Problem summary (from research)

- Light leaks are low-frequency; generating per-pixel at 4K/8K wastes ALU.

## RenderGraph integration

- Tier: Small → Full composite
- Fusion group: LensSystem
- Perception inputs: none
- Required graph features: Generate at fixed small res; upscale/composite to full.
- Reference: `shader_archtecture/RENDER_GRAPH_INTEGRATION.md` (LightLeak)

## Implementation plan

1. **Generate light leak at low resolution**
   - Allocate a small intermediate (e.g., 256×256 or 512×512).
   - Run `cs_light_leak` against the small target.
2. **Composite at full res**
   - Upscale during composite (linear filtering is sufficient).
   - Composite additively in the compositor/fused optics pass.
3. **Animation stability**
   - Ensure time-based evolution is resolution-independent (UV-space).

## Validation

- Visual: leak remains soft and organic; no aliasing.
- Performance: large speedup for leak generation at high output resolutions.

## Sprint mapping

- Primary: `Sprints/24o_volumetric_halfres_metalfx` (multi-res infrastructure)
