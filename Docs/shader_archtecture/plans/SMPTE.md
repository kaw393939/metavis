# Plan: SMPTE (test bars)

Source research: `shader_research/Research_SMPTE.md`

## Owners / entry points

- Shader: `Sources/MetaVisGraphics/Resources/SMPTE.metal`
- Kernels:
  - `fx_smpte_bars`

## Problem summary (from research)

- Branch-heavy region checks can cause divergence (though not typically performance-critical).
- Ensure the generated values are correct for the intended encoding / working space.

## RenderGraph integration

- Tier: Full
- Fusion group: Standalone (debug)
- Perception inputs: none
- Required graph features: Debug pattern; keep isolated.
- Reference: `shader_archtecture/RENDER_GRAPH_INTEGRATION.md` (SMPTE)

## Implementation plan

1. **Switch to index-based generation**
   - Use a constant color array and compute `index = int(uv.x * NumBars)`.
2. **Define color values explicitly**
   - Decide whether bars are defined in Rec.709 encoded space or linear working space.
   - Document and validate expected numeric levels (including PLUGE).
3. **Keep in `constant` address space** for cache friendliness.

## Validation

- Numeric: sample key regions and validate against reference values.

## Sprint mapping

- Primary: `Sprints/24j_shader_architecture_done`
