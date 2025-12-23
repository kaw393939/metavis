# Research: Lens.metal

**Target**: Apple Silicon M3 (Metal 3)
**Goal**: High Quality Distortion

## 1. Math
**Model**: Optical Distortion (Barrel/Pincushion).
$$ r_d = r_u (1 + k_1 r^2 + k_2 r^4) $$
**Precision**: Requires bicubic sampling for high-quality resizing/warping.

## 2. Technique: Vertex Displacement vs Frag
**Optimization**:
*   **Vertex**: Modify mesh grid vertices. Good for heavy distortion.
*   **Fragment**: Calculate UV per pixel. Higher quality.
*   **Strategy**: Use Fragment shader with **Bicubic Filtering** (M3 hardware supports bicubic weight calculation or efficient fetch).

## 3. M3 Architecture
**Sparse Textures**:
*   If distortion zooms in significantly, much of the source texture is unused. Standard textures load it all. Sparse textures (Tile Residency) could optimize this, but likely overkill.
**Latency**:
*   Dependent Texture Read (UV calculated in shader). M3 shader compiler is good at Hiding Latency if there are other ALU ops (like Grain) to interleave.

## Implementation Recommendation
Combine `Lens` distortion with `Vignette` and `Grain` into a single "Lens Characteristics" pass to amortize the texture read latency.
