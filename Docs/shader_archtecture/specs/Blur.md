# Blur.metal

## Purpose
Blur primitives used by multiple features.

## Kernels
- `fx_blur_h`
  - `sourceTexture` `texture(0)` (sample)
  - `destTexture` `texture(1)` (write)
  - `radius` `buffer(0)`

- `fx_blur_v`
  - Same bindings as `fx_blur_h`.

- `fx_spectral_blur_h`
  - `sourceTexture` `texture(0)` → `destTexture` `texture(1)`
  - `SpectralBlurParams` `buffer(0)`

- `fx_bokeh_blur`
  - `sourceTexture` `texture(0)` → `destTexture` `texture(1)`
  - `radius` `buffer(0)`

## Engine callsites
- PSO prewarm and dispatch: `Sources/MetaVisSimulation/MetalSimulationEngine.swift`.
- Multi-pass gaussian blur feature: `Sources/MetaVisSimulation/Features/StandardFeatures.swift`.

## Performance notes (M3+)
- Gaussian blur sample count scales with `radius`; keep `radius` bounded at the UX layer.
- Prefer half intermediates (already used in gaussian path) to reduce register pressure.
