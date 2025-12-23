# Plan: Noise (core library)

Source research: `shader_research/Research_Noise.md`

## Owners / entry points

- Shader library: `Sources/MetaVisGraphics/Resources/Noise.metal`
- No kernels here; this file provides inline noise functions used by other shaders.

## Problem summary (from research)

- Heavy procedural noise (FBM, 3D simplex) can be ALU/register expensive.

## RenderGraph integration

- Tier: N/A (library)
- Fusion group: N/A
- Perception inputs: none
- Required graph features: No kernel entry points; used by other shaders.
- Reference: `shader_archtecture/RENDER_GRAPH_INTEGRATION.md` (Noise)

## Implementation plan

1. **Introduce a 3D noise texture path**
   - Provide helper sampling APIs that accept a `texture3d<float>` tiling volume.
2. **Decide how the 3D volume is provisioned**
   - Option A: ship a small 3D noise asset and load as a Metal texture.
   - Option B: generate once at startup into a 3D texture.
3. **Keep ALU noise for lightweight cases**
   - Retain `hash`/interleaved gradient noise for cheap 2D noise.

## Validation

- Visual: noise continuity + tiling behavior is acceptable.
- Performance: heavy noise users switch from large ALU cost to texture sampling.

## Sprint mapping

- Primary: `Sprints/24j_shader_architecture_done`
