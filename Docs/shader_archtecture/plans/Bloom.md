# Plan: Bloom (from Research_Bloom.md)

## Shipping touchpoints
- Research: `shader_research/Research_Bloom.md`
- Shader: `Sources/MetaVisGraphics/Resources/Bloom.metal` (`fx_bloom_composite`)

## Issues identified in research
- Single-pass gaussian blur is expensive for large radii.
- Research recommends a dual-filter (Kawase-style) pyramid (downsample/upsample).

## RenderGraph integration

- Tier: Quarter/Half pyramid
- Fusion group: BloomSystem
- Perception inputs: none
- Required graph features: Requires tiered downsample/upsample pyramid orchestration.
- Reference: `shader_archtecture/RENDER_GRAPH_INTEGRATION.md` (Bloom)

## Holistic solution (fits 24j/24l)
- Make bloom a multi-resolution pipeline:
  - generate a mip pyramid (half/quarter…)
  - upsample and composite
- Ensure energy conservation by controlling weights.

## Concrete changes
- Replace current bloom approach with:
  - downsample passes leveraging bilinear hardware filtering
  - upsample tent filter and blend
  - composite using stable weights
- Express this as a multipass feature in the registry/graph.

## Validation
- Visual validation on HDR highlights.
- Measure bandwidth and frame time improvements on M3.

## Dependencies
- Sprint 24j (multi-resolution nodes) and 24l (post-stack integration).
