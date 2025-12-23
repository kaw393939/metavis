# Plan: Lens + Optics (system)

Source research: `shader_research/Research_Lens_Optics.md`

## RenderGraph integration

- Tier: Full (+ small intermediates for leaks)
- Fusion group: LensSystem
- Perception inputs: none
- Required graph features: May allocate small intermediates; composite back to full.
- Reference: `shader_archtecture/RENDER_GRAPH_INTEGRATION.md` (Lens_Optics)

## Scope

This plan covers the cross-shader “lens characteristics” grouping:

- `Lens.metal`
- `Vignette.metal`
- `SpectralDispersion.metal`
- `LightLeak.metal`

## Problems (from research)

- Vignette should be pure ALU; avoid full-frame pass if it can be inlined into a final pass.
- Lens distortion is a dependent texture read; hide latency with additional ALU work.
- Light leaks are low-frequency; generating at 8K is wasteful.
- Spectral dispersion is inherently multi-sample; keep taps minimal.

## Implementation plan

1. **Inline vignette** where it naturally belongs.
   - Prefer integrating into a final color/ODT pass or a fused lens system pass.
2. **Fuse lens + CA**
   - Make `fx_lens_system` the preferred dispatch for lens operations.
3. **Low-res light leak path**
   - Generate leak at 256–512 square; upscale + composite.
4. **Keep spectral dispersion minimal**
   - Maintain 3 taps; ensure sampling quality is acceptable.

## Validation

- Visual: optics stack matches previous look (or improves) with fewer passes.
- Performance: optics features no longer require multiple full-frame intermediates.

## Sprint mapping

- Primary: `Sprints/24l_post_stack_fusion`
