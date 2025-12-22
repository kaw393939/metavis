# Research: FilmGrain.metal

**Target**: Apple Silicon M3 (Metal 3)
**Goal**: Cinematic Grain Simulation

## 1. Math & Physics
**Physics**: Silver Halide crystals. Not Gaussian noise.
**Characteristics**: Clumping, Blue Noise spectra (high frequency lacking low freq), Luminance dependent (midtones > highlights).

## 2. Technique: Texture Overlay
**Current**: Procedural hash? (ALU heavy, potentially repeating patterns).
**Solution**: **3D Blue Noise Texture**.
*   Load a precalculated 64x64x64 Block which contains tileable Blue Noise.
*   Sample at `(uv + offset)`.
*   Apply **Luminance Masking**: $Grain += Noise \cdot (Luma \cdot (1 - Luma))$.

## 3. M3 Architecture
**Texture Cache**:
*   Small 3D textures stay hot in L1 cache.
*   Texture sampling is cheaper than complex ALU hash functions (Gold noise, etc.) for high quality.

## Implementation Recommendation
Switch to **3D Blue Noise Texture** sampling.
