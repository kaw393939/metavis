# Volumetric Nebula Refinement Notes (2025-12-20)

Scope: refinement pass only (no architectural rewrite). Target kernel: `fx_volumetric_nebula`.

## Goals implemented

1) Density-driven subtle chromatic divergence + neutralized rims
- Emission color gets a very small density-driven channel divergence (kept under ~5% shift) to add “spectral separation” without LUT look-hacks.
- Forward-scattering rim highlights are gently driven toward neutral (desaturated) at low density to prevent cyan/colored rim halos.

2) Gradient-driven edge sharpness modulation (no thresholds)
- Uses a stable, cheap approximation of density gradient along the ray (difference vs previous step) to detect edges.
- Applies smooth edge erosion preferentially in low-density boundary regions.

3) Mid-tone density remap (30–60%)
- Applies a gentle log-like remap only within a windowed 0.30–0.60 normalized density band to lift/reveal internal structure without flattening silhouettes.

## Stability / ACEScg considerations
- All operations remain in linear space (no gamma/tonemap here).
- Removed threshold gating in the density noise modulation (replaced with smoothstep gating) to reduce temporal popping under animation.
