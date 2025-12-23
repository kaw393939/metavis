# Plan: DepthOne (from Research_DepthOne.md)

## Shipping touchpoints
- Research: `shader_research/Research_DepthOne.md`
- Shader: `Sources/MetaVisGraphics/Resources/DepthOne.metal` (`depth_one`)

## Issues identified in research
- Clearing depth via compute defeats Hi-Z compression and forces memory writes.

## Holistic solution
- Use depth attachment loadAction clear with `clearDepth = 1.0`.

## RenderGraph integration

- Tier: Full
- Fusion group: Standalone (debug)
- Perception inputs: none
- Required graph features: Debug output; keep isolated from fused pipelines.
- Reference: `shader_archtecture/RENDER_GRAPH_INTEGRATION.md` (DepthOne)

## Concrete changes
- Deprecate `depth_one` compute usage.
- Ensure render passes that need depth use:
  - `depthAttachment.loadAction = .clear`
  - `clearDepth = 1.0`

## Validation
- Confirm depth-dependent passes still behave correctly.

## Dependencies
- Sprint 24m.
