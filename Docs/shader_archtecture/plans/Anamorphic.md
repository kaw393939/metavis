# Plan: Anamorphic (from Research_Anamorphic.md)

## Shipping touchpoints
- Research: `shader_research/Research_Anamorphic.md`
- Shader: `Sources/MetaVisGraphics/Resources/Anamorphic.metal` (`fx_anamorphic_composite`)

## Issues identified in research
- Horizontal streak pass is ideal for threadgroup memory optimization.
- For small radii, SIMD shuffle can share samples across lanes.

## Holistic solution
- Treat streaks as a specialized horizontal filter fed by the shared highlights data.

## RenderGraph integration

- Tier: Half/Quarter threshold + Full composite
- Fusion group: BloomSystem
- Perception inputs: none
- Required graph features: Reduced-res streak extraction; composite to full.
- Reference: `shader_archtecture/RENDER_GRAPH_INTEGRATION.md` (Anamorphic)

## Concrete changes
- Rewrite horizontal streak pass to:
  - load a row segment into `threadgroup` memory
  - barrier
  - blur via shared reads
- Optional optimization path:
  - if radius < 32, use `simd_shuffle_xor`-based sharing

## Validation
- Compare streak shape/energy to current kernel.
- Profile bandwidth reduction vs naive sampling loop.

## Dependencies
- Sprint 24j (multi-res/highlights staging).
