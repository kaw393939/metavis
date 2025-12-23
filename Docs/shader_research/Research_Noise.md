# Research: Noise.metal

**Target**: Apple Silicon M3 (Metal 3)
**Goal**: ALU vs Bandwidth Balance

## 1. Math
**Function**: Perlin, Simplex, Worley noise.
**Cost**:
*   Simplex 3D: ~30-50 ALU ops.
*   FBM (Octaves): $Cost \times Octaves$.

## 2. Technique: Precomputed 3D Noise
**Research**: Random-access noise (like Gradient Noise) causes high register pressure.
**Optimization**:
*   **3D Texture**: Store a 128^3 tiling noise volume.
*   **Sample**: `texture.sample(s, pos * freq)`.
*   **Cost**: 1 Texture Fetch (very fast with L1 cache) + interpolation.

## 3. M3 Architecture
**ALU/Tex Balance**:
*   M3 has huge arithmetic throughput, but typically for FBM (5-8 octaves), 8 fetches is cleaner and more predictable than 400 ALU instructions.
*   Also allows for **Blue Noise** characteristics which are hard to calculate analytically.

## Implementation Recommendation
Implement **3D Texture Sampling** for heavy noise users. Keep ALU for lightweight 2D noise.
