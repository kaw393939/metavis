# Executive Summary: Metal Shader Review

**Scope**: 32 Metal Files in `Sources/MetaVisGraphics`
**Target Compliance**: Studio Grade ACES 1.3
**Target Architecture**: Apple Silicon M3 (Metal 3)

## High-Level Assessment
The current shader codebase is functional but "prosumer" grade. It lacks the rigorous physical accuracy required for "Studio Grade" VFX and fails to leverage the unique hardware capabilities of the Apple M3 GPU (Tile Memory, NPU helpers, VRS), resulting in suboptimal performance for 8K workflows.

## Critical Risks (Immediate Action Required)
1.  **Explosive Complexity in `MaskedBlur`**: The `fx_masked_blur` kernel uses a naive $O(R^2)$ variable-radius loop. For a 64px radius, this performs ~4,000 reads *per pixel*. This will likely cause TDR/GPU hangs on 4K/8K renders.
    *   *Fix*: Replace with Mipmap-based blur or `MPSImageGaussianBlur`.
2.  **ACES Non-Compliance**: The `ACES.metal` implementation relies on approximate curve fits (Stephen Hill's fitted RRT) rather than the standard analytical ACES RRT + ODT. HDR ODTs are incorrectly implemented (Reinhard-style).
    *   *Fix*: Implement full ACES 1.3 analytical RRT+ODT or Reference LUTs.
3.  **Missing Temporal Stability**: `Temporal.metal` implements a naive blend without Motion Vector reprojection. This causes "ghosting" on moving subjects.
    *   *Fix*: Implement Velocity buffers and Reprojection logic (TAA).

## Performance Optimization (M3 Specifics)
1.  **Tile Memory Compositing**: The layer blending system (`Compositor.metal`) reads/writes main memory for every layer.
    *   *Upgrade*: Use **Metal Render Command Encoder** with **Programmable Blending** (reading `color(0)`) to compose layers entirely in on-chip Tile Memory, saving gigabytes of bandwidth per frame.
2.  **Variable Rate Shading (VRS)**: `VolumetricNebula.metal` performs heavy raymarching at full resolution.
    *   *Upgrade*: Use M3's VRS to shade low-frequency gas clouds at 1/4 resolution (2x2 blocks).
3.  **Branchless Color Math**: `ColorSpace.metal` uses branching conditional logic (`if/else`) for transfer functions.
    *   *Upgrade*: Refactor to branchless `select()` or vector math to maximize SIMD lane utilization.

## Quality Upgrades
1.  **Face Enhance**: Currently uses a low-quality 4-tap Bilateral Filter ("cross" artifacts).
    *   *Upgrade*: Switch to O(1) **Guided Filter** (or `MPSImageGuidedFilter`) for studio-quality skin smoothing.
2.  **False Color**: Uses computationally expensive polynomials.
    *   *Upgrade*: Use a standard 1D Texture LUT.

## Implementation Roadmap
See `implementation_plan.md` for the step-by-step engineering plan to address these findings.
