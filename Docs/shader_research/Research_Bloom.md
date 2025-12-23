# Research: Bloom.metal

**Target**: Apple Silicon M3 (Metal 3)
**Goal**: Physically Based Energy Conservation

## 1. Math & Physics
**Physics**: Light scattering in atmosphere/lens elements.
**Energy Conservation**: $L_{out} = L_{in} + k \cdot L_{scatter}$. The scattered energy must come *from* the input; typically implicit in HDR, but "adding" bloom shouldn't blow out the image energy artificially.
**Problem (Current)**: Standard Gaussian is expensive ($O(R^2)$).

## 2. Technique: Dual Filtering (Kawase)
**Standard 2025**:
*   **Downsample**: 13-tap bilinear filter (5 texture fetches exploiting linear filtering).
*   **Upsample**: 3x3 Tent filter (9-tap) blended with existing higher-res mip.
*   **Quality**: Very smooth, large radius, minimal ALU/Bandwidth.

## 3. M3 Architecture
**Bilinear Hardware**:
*   M3 has dedicated texture filtering hardware. Using 13-tap layouts that leverage `linear` sampling (fetching 4 pixels for the cost of 1) is key.
**Memory Hierarchy**:
*   Downsampling creates a "Pyramid". Each successive lower level is 4x smaller, fitting easily into the M3's huge **System Level Cache (SLC)**.

## Implementation Recommendation
Replace Single-Pass Gaussian with **Dual Filter Pyramid**.
