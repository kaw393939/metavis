# Plan: ACES (from Research_ACES.md)

## Shipping touchpoints
- Research: `shader_research/Research_ACES.md`
- Shader(s): `Sources/MetaVisGraphics/Resources/ACES.metal` (and/or related ACES transforms)
- Call path context: `shader_archtecture/REGISTRY.md`

## Issues identified in research
- Current RRT/ODT is a fitted approximation; missing ACES 1.3 components.
- Missing **Reference Gamut Compression** and ODT sweeteners (red modifier, glow).
- Branching transfer logic should be replaced with branchless/select where possible.

## RenderGraph integration

- Tier: Full
- Fusion group: FinalColor
- Perception inputs: none
- Required graph features: Graph-level IDT/ODT placement; fuse where possible.
- Reference: `shader_archtecture/RENDER_GRAPH_INTEGRATION.md` (ACES)

## Holistic solution (fits 24j/24k)
- Keep the “golden thread”: inputs converted to ACEScg, then FX, then display transform.
- Implement ACES 1.3 components as **analytical ALU** on M3 (bandwidth-friendly).
- Version the ACES pipeline explicitly (so exports/preview can select exact behavior).

## Concrete changes
- Implement ACES 1.3 analytical chain pieces needed by our pipeline:
  - Reference Gamut Compression (RGC)
  - RRT + ODT segments using segmented splines (avoid LUT bandwidth)
  - Optional sweeteners: glow + red modifier
- Ensure branchless code style:
  - Replace `if/else` toes with `select()` patterns.
- Define parameterization and defaults (debug toggles allowed for validation, not exposed to UX unless already present).

## Validation
- Build a small “ACES validation set”:
  - saturated brights (blue LED / lasers)
  - skin tones
  - high dynamic range highlights
- Compare outputs between old and new paths, document expected deltas.

## Dependencies
- Sprint 24k (ACES 1.3 correctness) is the primary home.
