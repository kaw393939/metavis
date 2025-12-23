# Plan: MaskSources (from Research_MaskSources.md)

## Shipping touchpoints
- Research: `shader_research/Research_MaskSources.md`
- Shader: `Sources/MetaVisGraphics/Resources/MaskSources.metal` (`source_person_mask`)

## Issues identified in research
- Mask resampling/filtering needs explicit control (nearest vs linear).
- If it’s a pure copy, blit should replace compute.

## Holistic solution
- Treat masks as a resource class with explicit sampling policy.

## RenderGraph integration

- Tier: Full
- Fusion group: MaskOps
- Perception inputs: yes: source_person_mask
- Required graph features: Perception→GPU bridge; outputs .r8Unorm mask texture.
- Reference: `shader_archtecture/RENDER_GRAPH_INTEGRATION.md` (MaskSources)

## Concrete changes
- If no resample needed: replace with `MTLBlitCommandEncoder` copy.
- If resample needed:
  - keep shader
  - expose sampler choice and default policy per mask type.

## Validation
- Confirm mask edge behavior matches expectations (binary vs AA).

## Dependencies
- Sprint 24j (resource policy).
