# Plan: FilmGrain (from Research_FilmGrain.md)

## Shipping touchpoints
- Research: `shader_research/Research_FilmGrain.md`
- Shader: `Sources/MetaVisGraphics/Resources/FilmGrain.metal` (`fx_film_grain`)

## Issues identified in research
- Procedural hash noise is ALU-heavy and can repeat.
- Research recommends a small tileable 3D blue-noise texture with luminance masking.

## Holistic solution
- Add a shared noise-texture resource strategy usable by grain and other effects.

## RenderGraph integration

- Tier: Full
- Fusion group: FinalColor (inline ALU)
- Perception inputs: none
- Required graph features: Fuse into final full-frame when possible.
- Reference: `shader_archtecture/RENDER_GRAPH_INTEGRATION.md` (FilmGrain)

## Concrete changes
- Introduce a 3D blue-noise texture (e.g. 64^3) as a resource.
- Update grain kernel to:
  - sample `(uv + timeOffset)` into noise volume
  - apply luminance-dependent mask (mid-tones emphasized)

## Validation
- Visual: ensure no obvious tiling and stable temporal behavior.
- Perf: confirm lower ALU pressure.

## Dependencies
- Sprint 24l if grain is fused into PostStack.
