# Plan: Lens (distortion / lens system)

Source research: `shader_research/Research_Lens.md`

## Owners / entry points

- Shader: `Sources/MetaVisGraphics/Resources/Lens.metal`
- Kernels:
  - `fx_lens_system`
  - `fx_lens_distortion_brown_conrady`
  - `fx_spectral_ca`

## Problem summary (from research)

- Distortion is a dependent texture read; quality depends on sampling (bicubic ideal).
- Best performance comes from fusing lens characteristics into fewer full-frame passes.

## Target architecture fit

- Fuse distortion + vignette + grain where possible (latency hiding + bandwidth reduction).

## RenderGraph integration

- Tier: Full
- Fusion group: LensSystem
- Perception inputs: none
- Required graph features: Lens effects should be fused as a coherent system.
- Reference: `shader_archtecture/RENDER_GRAPH_INTEGRATION.md` (Lens)

## Implementation plan

1. **Converge on a single “lens system” kernel**
   - `fx_lens_system` should optionally include: distortion, vignette, CA, grain (via function constants).
2. **Sampling quality**
   - Where possible, switch to higher-quality reconstruction (bicubic approximation) for distortion.
3. **Latency hiding**
   - Compute UV warps and lens math first; interleave ALU (vignette/grain) before sampling where feasible.
4. **Parameterization**
   - Ensure Brown–Conrady params are stable and documented (k1/k2, center, scale).

## Validation

- Visual: distortion is stable and does not shimmer with animation.
- Performance: fewer passes and lower bandwidth.

## Sprint mapping

- Primary: `Sprints/24l_post_stack_fusion` (post-stack pass fusion)
