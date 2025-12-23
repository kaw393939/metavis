# Research: Lens & Optics Shaders

**Files**:
- `Lens.metal`
- `Vignette.metal`
- `SpectralDispersion.metal`
- `LightLeak.metal`

**Target**: Apple Silicon M3 (Metal 3)

## 1. Lens Distortion (`Lens.metal`)
### Math (Brown-Conrady)
*   **Model**: $r_d = r_u (1 + k_1 r^2 + k_2 r^4 + ...)$.
*   **Performance**: Requires dependent texture read (UV is calculated per pixel).
*   **M3 Optimization**:
    *   **Latency Shielding**: Calculate UVs, then do *other* ALU work (like Vignette or Grain) before consuming the texture sample. This hides the memory latency.
    *   **Sparse Textures**: For >8K, use Sparse Textures to only load the distorted visible regions.

## 2. Spectral Dispersion (`SpectralDispersion.metal`)
### Math
*   **Technique**: Chromatic Aberration. Offset R, G, B standard samples.
*   **Optimization**:
    *   **Sample Count**: Current uses 3 samples (R, G, B). High quality requires spectral integration (many samples).
    *   **M3**: Use **Texture Gather** (`gather()`) to read 4 components at once if possible, though for dispersion offsets are different.
    *   **Fallback**: Stick to 3 taps. It's cheap.

## 3. Vignette (`Vignette.metal`)
### Math (Natural Illumination)
*   **Model**: $\cos^4(\theta)$ law.
*   **Optimization**:
    *   **Pure ALU**: Do not sample a "Vignette Texture". Calculate analytically.
    *   **Integration**: Inline this function into the **Tone Mapping** or **ACES ODT** pass to avoid reading/writing the 8K frame just to darken corners.

## 4. Light Leaks (`LightLeak.metal`)
### Math
*   **Technique**: Procedural additive shapes.
*   **Optimization**:
    *   **Compute**: Generate the shape on a low-res (512x512) texture, then upscale-composite. Generating per-pixel 8K noise for a soft blob is wasteful.

## Implementation Plan
1.  **Inline Vignette**: Move logic to `ToneMapping` or `ColorSpace` final pass.
2.  **Optimize Lens**: Ensure `Lens.metal` logic is pre-calculated or combined with other distortion passes.
