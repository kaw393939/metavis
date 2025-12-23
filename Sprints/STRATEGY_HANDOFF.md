# Strategic Roadmap & Technical Directives (Sprints 24-35)

> **To the Coding Agent**: This document outlines the technical strategy for transforming `metavis_render` into a studio-grade engine. Your immediate task is to execute **Sprint 24i** (Performance) and **Sprint 24n** (QC) based on the research findings below.

## Phase 1: The Foundation (Sprint 24)

The goal of Sprint 24 is to ensure correct colors, $O(1)$ performance, and M3 hardware utilization.

**Platform Targets (2024+ Hardware Only)**:
*   **Mac**: M3, M4, and newer (Apple Silicon only). No Intel support.
*   **Mobile**: iPhone 15 Pro (A17 Pro) and newer. iPad M4.
*   **XR**: Vision Pro.

**Implications**:
*   No fallback code for legacy GPUs.
*   Assume native **SIMD-scoped operations**, **Mesh Shaders**, and **Raytracing acceleration** are available.
*   Assume **Tile Memory/Imageblocks** are always available.

### Critical Priority (Immediate Implementation)

#### 1. Masked Blur Optimization (Sprint 24i)
*   **Problem**: `MaskedBlur.metal` currently uses an $O(R^2)$ variable-radius loop. This explodes performance at large radii (e.g., > 100px).
*   **Directive**: Refactor to use **Mipmap Interpolation**.
    1.  Generate a mip chain for the source image.
    2.  In the shader, sample `source.sample(sampler, uv, level(blur_radius_normalized * max_mips))`.
    3.  This makes the blur cost $O(1)$ regardless of radius.
    4.  See `shader_research/Research_MaskedBlur.md` for details.

#### 2. QC Fingerprint Parallel Reduction (Sprint 24n)
*   **Problem**: `QCFingerprint.metal` uses `atomic_fetch_add` on global memory for every pixel. This causes massive contention and serialization.
*   **Directive**: Implement **3-Stage Parallel Reduction**:
    1.  **SIMD Level**: Use `simd_sum` to reduce 32 pixels to 1 value per threadgroup.
    2.  **Threadgroup Level**: Write to `threadgroup` memory and barrier.
    3.  **Global Level**: Only the first thread of the threadgroup writes the final sum to main memory using atomics.
    4.  See `shader_research/Research_QCFingerprint.md` (implied).

---

## Phase 2: Visual Fidelity (Sprints 24k, 24l, 24o)

Once performance is stable, move to visual correctness.

#### 3. ACES 1.3 Pipeline (Sprint 24k)
*   **Directive**: Replace the entire color pipeline with **ACES 1.3**.
    *   Implement `ACES_red_mod` and `ACES_glow` sweeteners.
    *   Use analytical approximations (splines) for the RRT/ODT to avoid 3D LUT bandwidth.
    *   See `Sprints/24k_aces13_color_pipeline/README.md`.

#### 4. Post-Stack Fusion (Sprint 24l)
*   **Directive**: Combine `Bloom`, `LensDistortion`, `Grain`, and `Vignette` into a single "Post Process" uber-shader.
    *   This reduces VRAM round-trips by 3x.
    *   Reuse Bloom mipmaps for Halation.
    *   See `Sprints/24l_post_stack_fusion/README.md`.

#### 5. Volumetric Optimization (Sprint 24o)
*   **Directive**: Decouple volumetric rendering resolution.
    *   Render fog/clouds at half or quarter resolution.
    *   Use `MetalFX` (Spatial or Temporal) to upscale to full screen.
    *   See `Sprints/24o_volumetric_halfres_metalfx/README.md`.

---

## Phase 3: The Future (Sprints 26-35)

These features rely on your work in Phase 1 & 2.

*   **Sprint 26 (Disney PBR)**: Needs the ACES pipeline (Sprint 24k) to handle high-dynamic-range lighting correctly.
*   **Sprint 31 (Collaboration)**: Needs the deterministic QC fingerprints (Sprint 24n) to verify state synchronization between users.
*   **Sprint 34 (AI Director)**: Needs the $O(1)$ performance (Sprint 24i) so the AI can "try" 100 variations of an edit in real-time.

## Reference Materials
All detailed research notes are located in `shader_research/`.
- `Research_MaskedBlur.md`
- `Research_ACES.md`
- `Research_Bloom.md`
- ...and others.

**Execute Sprint 24i and Sprint 24n first.**
