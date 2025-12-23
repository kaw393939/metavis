# Plan: Volumetric (screen-space godrays)

Source research: `shader_research/Research_Volumetric.md`

## Owners / entry points

- Shader: `Sources/MetaVisGraphics/Resources/Volumetric.metal`
- Kernels:
  - `fx_volumetric_light`

## Problem summary (from research)

- Radial sampling is expensive at full resolution.

## RenderGraph integration

- Tier: Half/Quarter + upscale
- Fusion group: VolumetricSystem
- Perception inputs: optional depth/mask later
- Required graph features: Tiered execution + upscale (MetalFX if available).
- Reference: `shader_archtecture/RENDER_GRAPH_INTEGRATION.md` (Volumetric)

## Implementation plan

1. **Downsample volumetric pass**
   - Run volumetric at 1/2 or 1/4 resolution.
2. **Upscale**
   - Prefer `MTLFXSpatialScaler` if available; otherwise bicubic-ish upscale.
3. **Composite**
   - Composite into the main frame with appropriate intensity/occlusion.

## Validation

- Visual: no blockiness/banding after upscale.
- Performance: volumetric cost scales with reduced resolution.

## Sprint mapping

- Primary: `Sprints/24o_volumetric_halfres_metalfx`
