# Plan: Procedural (core SDF / shapes)

Source research: `shader_research/Research_Procedural.md`

## Owners / entry points

- Shader library: `Sources/MetaVisGraphics/Resources/Procedural.metal`
- No kernels here; this file provides procedural field functions used by other shaders.

## Problem summary (from research)

- Procedural shapes should be anti-aliased using derivative-based AA (`fwidth`) for crispness across resolutions.

## RenderGraph integration

- Tier: N/A (library)
- Fusion group: N/A
- Perception inputs: none
- Required graph features: No kernel entry points; used by other shaders.
- Reference: `shader_archtecture/RENDER_GRAPH_INTEGRATION.md` (Procedural)

## Implementation plan

1. **Add derivative-based AA helpers**
   - Provide helpers that compute an AA width via `fwidth(dist)` and use `smoothstep`.
2. **Update SDF shape functions / operators**
   - Ensure any shape alpha generation uses the derivative AA helper (not a fixed epsilon).
3. **Keep branching minimal**
   - Prefer `mix`/`select` over complex `if` trees in hot paths.

## Validation

- Visual: shapes remain crisp and stable at 4K/8K.

## Sprint mapping

- Primary: `Sprints/24j_shader_architecture_done`
