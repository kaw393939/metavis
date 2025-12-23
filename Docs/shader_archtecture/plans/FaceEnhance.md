# Plan: FaceEnhance (beauty / skin smoothing)

Source research: `shader_research/Research_FaceEnhance.md`

## Owners / entry points

- Shader: `Sources/MetaVisGraphics/Resources/FaceEnhance.metal`
- Kernels:
  - `fx_face_enhance`
  - `fx_beauty_enhance`

## Problem summary (from research)

- Current bilateral approach (low tap count) can posterize / produce cross artifacts.
- A guided filter provides edge-preserving smoothing with $O(1)$ complexity (independent of radius).

## Target architecture fit

- Prefer MPS where it wins: `MPSImageGuidedFilter` (or equivalent) for speed and quality.

## RenderGraph integration

- Tier: Full (face ROI)
- Fusion group: MaskOps (pre-final)
- Perception inputs: consumes face/person mask; segmentation later
- Required graph features: ROI-aware execution preferred; depends on mask source policy.
- Reference: `shader_archtecture/RENDER_GRAPH_INTEGRATION.md` (FaceEnhance)

## Implementation plan

1. **Decide implementation path**
   - Option A (preferred): integrate `MPSImageGuidedFilter` (GPU) and remove/limit custom bilateral.
   - Option B: implement separable guided filter using box-filter passes.
2. **Pipeline wiring**
   - Define intermediate textures for mean/cov steps (or use MPS-managed intermediates).
   - Ensure textures are in the working color space (ACEScg linear).
3. **Masking / face isolation**
   - If face masks exist, apply guided smoothing only inside face region, with a soft falloff.
4. **Quality controls**
   - Expose radius/epsilon equivalents via parameters.

## Validation

- Visual: removes cross artifacts; preserves edges (eyes, lips).
- Performance: guided filter path is faster than custom loops at common radii.

## Sprint mapping

- Primary: `Sprints/24m_render_vs_compute_migrations` (MPS adoption + pipeline swaps)
