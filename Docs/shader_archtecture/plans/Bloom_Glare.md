# Plan: Bloom + Glare system (from Research_Bloom_Glare.md)

## Shipping touchpoints
- Research: `shader_research/Research_Bloom_Glare.md`
- Shaders: `Bloom.metal`, `Halation.metal`, `Anamorphic.metal`

## Issues identified in research
- Bloom should be dual-filter pyramid and energy-conserving.
- Halation should reuse bloom pyramid instead of separate blur.
- Anamorphic streaks should use SIMD/threadgroup optimizations.

## Holistic solution
- Build a single **Highlights Pyramid** stage:
  - threshold once
  - generate pyramid once
  - feed bloom/halation/anamorphic from that shared data

## RenderGraph integration

- Tier: Quarter/Half pyramid
- Fusion group: BloomSystem
- Perception inputs: none
- Required graph features: Requires tiered pyramid; composite to full.
- Reference: `shader_archtecture/RENDER_GRAPH_INTEGRATION.md` (Bloom_Glare)

## Concrete changes
- Refactor bloom to pyramid generation.
- Halation:
  - remove standalone blur pass
  - sample a bloom mip level and tint
- Anamorphic:
  - implement horizontal shared-memory blur, optionally SIMD shuffle for small radii

## Validation
- Ensure bloom/halation/anamorphic interplay doesn’t double-count energy.
- Profile pyramid generation and cache behavior on M3.

## Dependencies
- Sprint 24j (multi-res), 24l (fusion/integration).
