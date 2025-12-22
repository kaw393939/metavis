# Shader Review: Optical & Lens Effects (Batch 1)

**Files**: 
- `Anamorphic.metal`
- `Bloom.metal`
- `Halation.metal`
- `Lens.metal`
- `Vignette.metal`
- `SpectralDispersion.metal`
- `LightLeak.metal`

**Target**: Apple Silicon M3 (Metal 3)

## 1. Bloom (`Bloom.metal`)
**Status**: Strong implementation (Dual Filter downsample, Cinematic Golden Angle upsample). M3 ready.
*   **Strengths**: Using Golden Angle spiral prevents "box" artifacts. Energy conserving logic in composite.
*   **Optimizations**:
    *   **Tile Memory**: The final `fx_bloom_composite` reads `source`, `bloom` and writes `dest`. This is a classic "additive blend" that should be a Fragment Shader with **Programmable Blending**.
    *   **Memory Bandwidth**: The downsample/upsample chain consumes significant bandwidth. Ensure intermediate textures are `private` storage.
    *   **FP16**: The entire bloom chain can safely run in `half` precision. The file uses `float` for UVs (good) but `half` for colors (good).
*   **Compliance**: Physically plausible (energy conservation).

## 2. Halation (`Halation.metal`)
**Status**: Physically based loop, good dithering.
*   **Optimizations**:
    *   **Branching**: `if (uniforms.radialFalloff != 0)` is a uniform condition, so it's coherent. Zero cost.
    *   **Tile Shading**: `fx_halation_composite` is another screen/add blend. Should be merged into the main Uber-Shader (Raster) or use Programmable Blending.
    *   **Texture Access**: Reading 32-bit floats for mask generation. Can likely reduce to 16-bit.

## 3. Lens Distortion (`Lens.metal`)
**Status**: Standard Brown-Conrady. coupled with CA.
*   **Optimizations**:
    *   **Unified Kernel**: `fx_lens_system` handles both distortion and CA. This is efficient (one texture read per channel).
    *   **Sampling**: Uses dependent texture reads (UVs depend on calculations). This is high latency.
    *   **M3 Specific**: Use **Sparse Textures** (Resident Textures) if the source resolution is massive (8K+).
    *   **Sampler**: `s` is declared `constexpr`. Good.

## 4. Anamorphic (`Anamorphic.metal`)
**Status**: Two-pass streak generation.
*   **Critique**:
    *   The "Threshold" pass is redundant with Bloom's threshold.
    *   **Optimization**: Merge `fx_anamorphic_threshold` with `fx_bloom_prefilter`? They both just extract brights. Reusing the Bloom extraction for Anamorphic streaks saves a full read/write pass.

## 5. Vignette (`Vignette.metal`)
**Status**: Physically based (Cos^4 law).
*   **Optimizations**:
    *   **Arithmetic Intensity**: High (sqrt, pow, mix). This is ALU heavy.
    *   **M3**: ALUs are cheap, bandwidth is expensive. This is a perfect candidate to be an **inline function** in the final Composition/ToneMapping Uber-Shader rather than a separate pass. Reading/Writing a 4K texture just to darken corners is wasteful of bandwidth.

## Summary Action Points
- [ ] **Bloom**: Keep structure, move Composite to Raster pipeline.
- [ ] **Anamorphic**: Consolidate Threshold pass with Bloom.
- [ ] **Vignette**: "Inline" this logic into the final ODT/ToneMap shader to save 100% of bandwidth for this pass.
- [ ] **Lens**: Ensure `half` precision usage for UV calculations where valid.
