# Shader Review: ToneMapping.metal

**File**: `Sources/MetaVisGraphics/Resources/ToneMapping.metal`  
**Reviewer**: Antigravity  
**Target Hardware**: Apple Silicon M3 (Metal 3)  
**Context**: Final Image Display Rendering

## Overview
This file applies the final grading curves to convert scene-linear data (ACEScg) into display-ready signals (Rec.709, Rec.2020 PQ).

## Compliance Issues
1.  **SDR Grading**: Uses `ACESFilm` (Narkowicz fit).
    *   *Issue*: This curve is "ACES-like" but not ACES. It lacks the complex hue skews and desaturation characteristics of the RRT.
    *   *Recommendation*: For Studio Grade, implement the **Common LUT Format (CLF)** loader or the analytic RRT+ODT, or at least a high-quality 3D LUT texture lookup `fx_apply_lut` that loads the official ACES `.cube`.
    *   *Note*: Narkowicz is fine for "Draft" or "Game" modes, but "Studio" requires exactness.
2.  **Gamma**: `pow(mapped, 1.0/2.2)` used for Rec.709.
    *   *Issue*: sRGB has a linear toe. Rec.709 camera OETF is `1/0.45` ≈ 2.22 but technically different. Standard sRGB monitor EOTF is usually purely 2.2 gamma or piecewise.
    *   *Fit*: For "display on Mac screen", using standard `linear_to_sRGB` (piecewise) from `ColorSpace.metal` is more accurate than simple `pow 2.2`.

## Apple Silicon M3 Optimizations

### 1. Sampling
*   **Current**:
    ```cpp
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float4 color = sourceTexture.sample(s, uv);
    ```
*   **Optimization**:
    *   Use `read(gid)` if the input and output resolution match (1:1 mapping). Sampling adds overhead (filtering logic) even if not needed.
    *   However, if this is the "Resolve" pass where we might be scaling (render at 1080p, display at 4K), sampling is correct.
    *   **Check**: In `MetalSimulationEngine.swift`, `internalRender` seems to match resolution usually. If logic confirms 1:1, switch to `read`.

### 2. Compute to Fragment (Render Pass)
*   **Opportunity**: Tone mapping is often the final step before display.
*   **Optimization**: Instead of writing to a generic texture then blitting to the `CAMetalLayer` executable, we should use a **Render Command Encoder** (Raster) directly into the drawable's texture.
    *   M3 Advantage: Framebuffer Compression (FBC).
    *   *Action*: Convert `fx_tonemap_aces` to a Fragment Shader for the "StudioView" display pass. Keep Compute version for "Export" pass.

## Usage in Simulation
*   **Pipeline**: Called by `fx_tonemap_aces` / `fx_tonemap_pq`.
*   **Criticality**: High. This defines the final pixel values seen by the user.

## Action Plan
- [ ] Replace Narkowicz fit with analytic RRT+ODT or 3D LUT support.
- [ ] Use correct `linear_to_sRGB` function instead of `pow 2.2`.
- [ ] Create a Fragment Shader variant for direct-to-swapchain rendering.
