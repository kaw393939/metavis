# Plan: VolumetricNebula (raymarched clouds)

Source research: `shader_research/Research_VolumetricNebula.md`

## Owners / entry points

- Shader: `Sources/MetaVisGraphics/Resources/VolumetricNebula.metal`
- Kernels:
  - `fx_volumetric_nebula`
  - `fx_volumetric_composite`

## Problem summary (from research)

- Raymarching is extremely expensive (steps × octaves).

## RenderGraph integration

- Tier: Half/Quarter + composite
- Fusion group: VolumetricSystem
- Perception inputs: optional depth later
- Required graph features: Early termination + reduced-rate execution; composite to full.
- Reference: `shader_archtecture/RENDER_GRAPH_INTEGRATION.md` (VolumetricNebula)

## Implementation plan

1. **Add early ray termination**
   - Break when alpha reaches a threshold (e.g. 0.99).
2. **Reduce shading rate / resolution**
   - Prefer running at reduced resolution first (1/2 or 1/4) and compositing.
   - If/when a render-pipeline version exists, evaluate Variable Rate Shading (VRS) support.
3. **Composite path**
   - Ensure composite respects depth/occlusion as appropriate.

## Validation

- Visual: stable clouds; no popping from early termination.
- Performance: substantial reduction vs full-res full-step raymarch.

## Sprint mapping

- Primary: `Sprints/24o_volumetric_halfres_metalfx`
