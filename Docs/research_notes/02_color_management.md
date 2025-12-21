# Research Note: Color Management Architecture

**Source Documents:**
- `COLOR_MANAGEMENT_ARCHITECTURE.md`
- `COLOR_PIPELINE_AUDIT.md` (Gap Analysis)
- `RGB_YUV_MATRIX_ANALYSIS.md` (Matrix Math)
- `PBR_PIPELINE_DEEP_DIVE.md` (Material Integration)

## 1. Executive Summary
The system employs a **Unified ACEScg Pipeline** designed to composite PBR materials, video footage, and procedural effects in a physically accurate, scene-linear working space (`compositing_space`). The pipeline uses 16-bit Float precision internally (`rgba16Float`) to preserve HDR range and eliminate banding, converting to display-referred colors (`sRGB` or `Rec.2020`) only at the final output stage via ACES RRT+ODT.

## 2. Core Architecture

### Color Spaces
| Stage | Space | Format | Gamut | Transfer Function |
|-------|-------|--------|-------|-------------------|
| **Input (Video)** | Rec.709 / P3 | `bgra8Unorm` | Rec.709/P3 | Gamma (~2.4) / Log |
| **Input (PBR)** | ACEScg | `rgba16Float` | AP1 | Linear |
| **Working** | **ACEScg** | `rgba16Float` | AP1 | **Linear** |
| **Output (SDR)** | Rec.709 | `bgra8Unorm` | Rec.709 | Gamma 2.4 (OETF) |
| **Output (HDR)** | Rec.2020 | `P010` (10-bit) | Rec.2020 | PQ (ST.2084) or HLG |

### Principles
1.  **Linearize Early:** All inputs (video, images) are converted to Linear ACEScg immediately.
2.  **Render Linear:** Lighting, blending, and effects happen in linear light.
3.  **Tone Map Once:** ACES RRT (Reference Rendering Transform) + ODT (Output Device Transform) is applied only at the very end.

## 3. Detailed Data Flow

### A. Input Normalization
-   **Video:** Hardware decode produces Gamma-encoded BGRA.
    -   *Technique:* Use `.bgra8Unorm_srgb` Metal texture format for auto-decoding to linear on sample.
    -   *Alternative:* Manual shader decode (`pow(rgb, 2.2)`) but `.srgb` is preferred for efficiency.
-   **Procedural:** Generated directly in Scene-Linear space.
    -   *Constraint:* Must interpret values as physical **Luminance** (nits), not perceptual color.
    -   *Control:* Use `Exposure` parameters (EV stops) rather than scaling inputs.
-   **PBR Materials:** BaseColor textures are typically sRGB; must be linearized on load.

### B. The PBR Connection (`PBR_PIPELINE_DEEP_DIVE.md`)
-   **Shading Model:** Disney Principled BRDF (Burley Diffuse + GGX Specular).
-   **Lighting:** Accumulation happens in Linear ACEScg.
-   **Pre-Integration:** PBR output is *not* tone-mapped locally. It returns high-dynamic-range linear values (often > 1.0) to the compositor.

### C. Output Pipeline & Tone Mapping
1.  **Tone Mapping Kernel:**
    -   Input: `rgba16Float` (Scene Linear).
    -   Process: `ACES_RRT(x) -> ACES_ODT(x)`.
    -   Output: Display-Ready Linear (0-1 range).
2.  **OETF (Optical-Electro Transfer Function):**
    -   Apply target display gamma (e.g., BT.709 Gamma 2.4).
3.  **YUV Encoding:**
    -   *Critical Step:* Convert RGB to YUV 4:2:0.
    -   **THE MATRIX FIX:** Metal uses **Column-Major** matrices. Standard row-major definition matrices must be transposed.
    -   *Standard BT.709 Matrix (Transposed for Metal):*
        ```metal
        half3x3 RGB_to_YUV_709 = half3x3(
            half3( 0.2126h, -0.1146h,  0.5000h), // Col 0 (Red input)
            half3( 0.7152h, -0.3854h, -0.4542h), // Col 1 (Green input)
            half3( 0.0722h,  0.5000h, -0.0458h)  // Col 2 (Blue input)
        );
        ```

## 4. HDR Strategy
-   **Internal:** The 16-bit pipeline fundamentally supports HDR. Values > 1.0 are preserved.
-   **Export:**
    -   Requires `AVAssetWriter` configuration for `AVVideoColorPrimaries_ITU_R_2020` and `AVVideoTransferFunction_SMPTE_ST_2084_PQ`.
    -   Requires 10-bit Pixel Format (`kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange`).
    -   *Note:* 8-bit pipeline crushes HDR highlights; switching to 10-bit export is mandatory for OLED support.

## 5. Critical Implementation Details
-   **Blue Noise Dithering:** For 8-bit SDR output, apply blue noise dither *before* gamma encoding/quantization to prevent banding in smooth gradients.
-   **Procedural Colors:** Must be authored as "Scene Linear" or tagged as "Display Referred" and inversely transformed. Mixing them blindly causes "muddy" or "washed out" colors.
-   **Validation:** Use `keith_color_test.json` (Blue Shirt) to verify matrix correctness. ΔE < 1.0 target.

## 6. Optimization
-   **Math:** Use `half` (16-bit) precision for all color math.
-   **Memory:** `rgba16Float` consumes 2x memory of `bgra8Unorm`. Use Tile-Based Deferred Rendering (TBDR) behaviors (`.memoryless` or `.private`) for intermediate buffers to minimize bandwidth.
