# Plan: ToneMapping (from Research_ToneMapping.md)

## Shipping touchpoints
- Research: `shader_research/Research_ToneMapping.md`
- Shader: `Sources/MetaVisGraphics/Resources/ToneMapping.metal` (`fx_tonemap_aces`, `fx_tonemap_pq`)
- Engine parameter binding: `Sources/MetaVisSimulation/MetalSimulationEngine.swift` (exposure/maxNits)

## Issues identified in research
- Current tone mapping uses Reinhard; research says it:
  - desaturates highlights
  - has incorrect contrast roll-off

## RenderGraph integration

- Tier: Full
- Fusion group: FinalColor
- Perception inputs: none
- Required graph features: Prefer last full-frame pass if not fused into ODT.
- Reference: `shader_archtecture/RENDER_GRAPH_INTEGRATION.md` (ToneMapping)

## Holistic solution (fits 24k/24l)
- Prefer analytical tone-scale (ALU) over LUT bandwidth.
- Align tone scale with the ACES display intent (SSTS) so post-stack fusion is safe.

## Concrete changes
- Replace Reinhard curve with **ACES SSTS (Single Stage Tone Scale)** analytical segmented spline.
- Ensure the tone scale is compatible with later fusion:
  - can be combined with vignette (multiply)
  - can host optional dither/grain hooks if desired

## Validation
- Image set focusing on highlight behavior:
  - specular highlights
  - saturated bright emissives
  - gray ramps
- Confirm no banding regressions and improved highlight saturation behavior.

## Dependencies
- Sprint 24k (ACES/tone-scale correctness).
