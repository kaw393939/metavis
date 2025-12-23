# Plan: MaskedBlur (variable blur)

Source research: `shader_research/Research_MaskedBlur.md`

## Owners / entry points

- Shader: `Sources/MetaVisGraphics/Resources/MaskedBlur.metal`
- Kernels:
  - `fx_masked_blur`

## Problem summary (from research)

- Variable blur radius per pixel cannot be done with naive variable-radius loops (warp divergence + $O(R^2)$).

## Target architecture fit

- Use hardware mip LOD sampling + trilinear interpolation to approximate blur in $O(1)$ per pixel.
- Requires: a mip pyramid for the source texture.

## RenderGraph integration

- Tier: Full
- Fusion group: Standalone
- Perception inputs: mask texture (often perception-derived)
- Required graph features: Requires mipmapped source (Mips support) for O(1) LOD sampling.
- Reference: `shader_archtecture/RENDER_GRAPH_INTEGRATION.md` (MaskedBlur)

## Implementation plan

1. **Precompute mip pyramid** for the source texture.
   - Prefer generating mips via Metal (`MTLBlitCommandEncoder.generateMipmaps(for:)`) when the texture is created/available.
   - Ensure the source texture supports mipmaps (mipmapped allocation) and `shaderRead` usage.
2. **Rewrite `fx_masked_blur`** to sample the source at LOD derived from mask.
   - `maskVal = maskTex.sample(...).r` (clamped to $[0,1]$)
   - `lod = maskVal * maxLOD`
   - `color = sourceTex.sample(s, uv, level(lod))`
3. **Radius/LOD mapping**
   - Define a perceptual mapping curve (e.g. quadratic) so artist-facing “radius” feels linear.
   - Keep mapping branchless (`mix`, `select`).
4. **Edge behavior**
   - Confirm sampler addressing (clamp vs mirror) matches expected look.
5. **Quality knobs**
   - Add a “max blur” control that effectively sets `maxLOD`.
   - Optional: add a subtle additional 2–4 tap blur at high LODs if the mip blur is too boxy.

## Validation

- Visual: confirm masked regions smoothly blur without ringing or stepping.
- Performance: verify masked blur cost becomes ~constant w.r.t. blur radius.
- Correctness: ensure no out-of-range LOD sampling on small textures.

## Sprint mapping

- Primary: `Sprints/24l_post_stack_fusion` (multi-res / pass fusion primitives)
