# Plan: FormatConversion (from Research_FormatConversion.md)

## Shipping touchpoints
- Research: `shader_research/Research_FormatConversion.md`
- Shader: `Sources/MetaVisGraphics/Resources/FormatConversion.metal` (`rgba_to_bgra`, `resize_bilinear_rgba16f`)

## Issues identified in research
- Some conversions can be eliminated entirely with texture views.

## Holistic solution
- Prefer zero-copy view reinterpretation/swizzle when supported.
- When compute is needed, ensure vectorized loads/stores.

## RenderGraph integration

- Tier: Full
- Fusion group: Standalone (export boundary)
- Perception inputs: none
- Required graph features: Pixel format contract matters (scene-linear vs display/output).
- Reference: `shader_archtecture/RENDER_GRAPH_INTEGRATION.md` (FormatConversion)

## Concrete changes
- First choice: replace conversion with `MTLTexture.makeTextureView(pixelFormat:)`.
- If not possible (usage/format constraints): keep compute but ensure `float4/half4` IO.

## Validation
- Verify pixel-format correctness and no channel swap regressions.

## Dependencies
- Sprint 24j (execution model / resource policy) or 24i (perf pass).
