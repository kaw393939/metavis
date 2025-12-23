# Plan: Utility shaders (from Research_Utilities.md)

## Shipping touchpoints
- Research: `shader_research/Research_Utilities.md`
- Shaders:
  - `FormatConversion.metal`
  - `Watermark.metal`
  - `MaskSources.metal`

## Issues identified in research
- Avoid unnecessary deep copies; unify resource policy.
- Prefer branchless watermark.

## Holistic solution
- Define a utilities policy:
  - view-based format reinterpretation first
  - blit copy second
  - compute as last resort

## RenderGraph integration

- Tier: N/A (support)
- Fusion group: N/A
- Perception inputs: none
- Required graph features: Helper plan (no direct RenderGraph node).
- Reference: `shader_archtecture/RENDER_GRAPH_INTEGRATION.md` (Utilities)

## Concrete changes
- Apply policies in engine codepaths that currently dispatch these kernels.

## Validation
- Add small regression tests for format conversion and mask copy behavior.

## Dependencies
- Sprint 24j.
