# Plan: StarField (procedural background)

Source research: `shader_research/Research_StarField.md`

## Owners / entry points

- Shader: `Sources/MetaVisGraphics/Resources/StarField.metal`
- Kernels:
  - `fx_starfield`

## Problem summary (from research)

- Avoid storing stars in memory; generate deterministically via spatial hashing.
- Keep register pressure under control: small N per cell + unrolled loops.

## RenderGraph integration

- Tier: Full
- Fusion group: Standalone
- Perception inputs: none
- Required graph features: Debug/background; may optionally fuse in volumetric debug paths.
- Reference: `shader_archtecture/RENDER_GRAPH_INTEGRATION.md` (StarField)

## Implementation plan

1. **Adopt spatial hashing**
   - Use a deterministic, fast hash (PCG-style) over integer cell coords.
2. **Neighborhood search**
   - 3×3 neighbor cells; N=1–2 stars per cell.
3. **Density control**
   - Adjust cell size to maintain density without increasing N.
4. **Branch control**
   - Keep loops fixed-size for better compilation and predictability.

## Validation

- Visual: stable star positions; no swimming with camera motion.
- Performance: no allocations / no buffer reads.

## Sprint mapping

- Primary: `Sprints/24j_shader_architecture_done` (procedural shader patterns)
