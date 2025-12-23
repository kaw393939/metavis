# Plan: Blur (from Research_Blur.md)

## Shipping touchpoints
- Research: `shader_research/Research_Blur.md`
- Shader: `Sources/MetaVisGraphics/Resources/Blur.metal` (`fx_blur_h`, `fx_blur_v`, `fx_bokeh_blur`)
- Feature manifests: gaussian blur is multipass in `StandardFeatures`.

## Issues identified in research
- Custom gaussian blur is hard to beat on M3; MPS is tuned.

## RenderGraph integration

- Tier: Half/Quarter where allowed; Full when required
- Fusion group: BloomSystem / MaskOps / Standalone (caller-dependent)
- Perception inputs: none
- Required graph features: Prefer MPS blur for primitives; tiered allocation required.
- Reference: `shader_archtecture/RENDER_GRAPH_INTEGRATION.md` (Blur)

## Holistic solution (fits 24j/24m)
- Treat blur as a platform primitive:
  - default to MPS where available
  - keep custom kernels only when semantics differ (e.g. bokeh, stylized blur)

## Concrete changes
- Replace gaussian blur chain with `MPSImageGaussianBlur` in the Swift engine.
- Keep `fx_bokeh_blur` as custom if it’s not trivially replaced.
- Ensure the feature registry can still compile blur as a node, even if the engine executes it via MPS.

## Validation
- Performance and output comparison (MPS vs current kernels) for a few radii.
- Ensure edge handling matches expectations.

## Dependencies
- Sprint 24j (engine execution model support) and/or 24i (perf pass).
