# Plan: Vignette (from Research_Vignette.md)

## Shipping touchpoints
- Research: `shader_research/Research_Vignette.md`
- Shader: `Sources/MetaVisGraphics/Resources/Vignette.metal` (`fx_vignette_physical`)

## Issues identified in research
- A dedicated fullscreen vignette pass is bandwidth-wasteful.

## RenderGraph integration

- Tier: Full
- Fusion group: FinalColor (inline ALU)
- Perception inputs: none
- Required graph features: Fuse into final full-frame when possible.
- Reference: `shader_archtecture/RENDER_GRAPH_INTEGRATION.md` (Vignette)

## Holistic solution (fits 24l)
- Fuse vignette multiplication into the final tone-map / ODT / post pass.

## Concrete changes
- Remove or de-prioritize standalone vignette kernel in the common path.
- Add vignette math into the fused PostStack / ToneMapping stage.
- Keep standalone kernel only if needed for modularity/testing.

## Validation
- Compare fused vs standalone outputs for identical parameters.

## Dependencies
- Sprint 24l (post-stack fusion).
