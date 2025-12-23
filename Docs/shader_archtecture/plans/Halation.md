# Plan: Halation (from Research_Halation.md)

## Shipping touchpoints
- Research: `shader_research/Research_Halation.md`
- Shader: `Sources/MetaVisGraphics/Resources/Halation.metal` (`fx_halation_composite`)

## Issues identified in research
- Separate blur/pyramid for halation is wasteful.
- Reuse bloom pyramid mip(s) and tint red/orange.

## Holistic solution
- Make halation a *consumer* of the shared highlights/bloom pyramid.

## RenderGraph integration

- Tier: Half/Quarter threshold + Full composite
- Fusion group: BloomSystem
- Perception inputs: none
- Required graph features: Threshold at reduced res; composite to full; fuse with bloom family.
- Reference: `shader_archtecture/RENDER_GRAPH_INTEGRATION.md` (Halation)

## Concrete changes
- Remove standalone halation blur stages.
- Modify composite stage to:
  - sample bloom mip 1 or 2
  - tint
  - add/composite with controlled intensity

## Validation
- Ensure halation is stable across exposures and doesn’t introduce hue shifts.

## Dependencies
- Sprint 24j (pyramid availability).
