# Research Note: VFX & Compositing Architecture

**Source Documents:**
- `VFX_ARCHITECTURE.md`
- `VIDEO_COMPOSITE_STAGE_DEEP_DIVE.md`
- `VFX_BLOOM_SYSTEM.md`
- `VFX_FILMGRAIN_SYSTEM.md`
- `VFX_OCCLUSION_PASS.md`

## 1. Executive Summary
The VFX system is a high-performance, Metal-based post-processing pipeline anchored by `CinematicLookPass`. It combines procedural effects (Bloom, Grain, Vignette) with AI-driven semantic effects (Occlusion, Background Blur).

**Critical Finding:** The current composite stage blends linear graphics with gamma-encoded video. This is mathematically incorrect and leads to "muddy" blending (approx 5% brightness error). This MUST be fixed in MetaVisKit2 by linearizing video *before* compositing.

## 2. Core Compositing Engine (`CompositePass`)
-   **Function:** Blends Video (Background), Graphics (Foreground), and UI.
-   **Current State:**
    -   Input: `.bgra8Unorm` (BT.709 Video, Gamma-encoded).
    -   Output: `.rgba16Float` (HDR container, but *still gamma encoded*).
    -   Logic: Porter-Duff "Over" blend.
-   **The Flaw:** Blending happens in Gamma space. 0.5 grey + 0.5 grey != 1.0 white in gamma space.
-   **Target Architecture:**
    1.  Video Decode (YUV) -> Linear ACEScg (Float16).
    2.  Graphics Render -> Linear ACEScg (Float16).
    3.  Composite -> Linear Blending.
    4.  VFX Chain -> Linear ACEScg.
    5.  Tone Map -> Output.

## 3. Cinematic Effects Pipeline (`CinematicLookPass`)
A linear chain of 13 effects. Key algorithms optimized for Apple Silicon:

### A. Physical Bloom
-   **Algorithm:** Jimenez Dual-Filter (13-tap Downsample, 12-tap Golden Angle Upsample).
-   **Why:** "Standard" box blur looks blocky. Golden Angle spiral creates cinematic, round bokeh.
-   **Performance:** ~5-8ms @ 1080p (5 mip levels).
-   **Format:** Full float16 precision to preserve "fireflies" (highlights > 1.0).

### B. Film Grain
-   **Algorithm:** Procedural Gaussian noise (Box-Muller transform) with **Luminance Masking**.
-   **Behavior:**
    -   Shadows/Midtones: 100% grain.
    -   Highlights: Reduced grain (mimics physical film emulsion saturation).
    -   *Additive* blend (physically correct for silver halide crystals).

### C. AI Occlusion ("Text Behind Person")
-   **Logic:** Uses `VisionProvider` (Segmentation) to create a mask.
-   **Compositing:** 3-layer blend.
    -   Layer 1: Text.
    -   Layer 2: Video (Foreground Subject).
    -   Layer 3: Video (Background).
-   **Cost:** ~20ms latency (dominated by Neural Engine inference).

## 4. Hardware Optimization Strategy
-   **Textures:** Strict use of `.private` storage mode (GPU only) for all intermediates to leverage Tile Based Deferred Rendering (TBDR) cache.
-   **Memory:** `TexturePool` reuses intermediate buffers. `CinematicLookPass` acquires/releases textures per effect to keep footprint low.
-   **Compute:** 16x16 threadgroups tailored for Apple GPU SIMD width (32).

## 5. Synthesis for MetaVisKit2
1.  **Fix the Gamma Blend:** The #1 priority is moving the *entire* video path to Linear ACEScg immediately after decode.
2.  **Unified Shader Library:** Consolidate `Bloom.metal`, `FilmGrain.metal`, etc. into a `MetaVisGraphics` framework.
3.  **Vision Integration:** Move from "One-shot" segmentation to "Persistent Session" segmentation (via `VNSequenceRequestHandler`) to fix the 20ms flickering latency in Occlusion.
4.  **Effect Graph:** The linear chain of 13 effects is rigid. A node-based graph (DAG) would allow dynamic reordering (e.g. Grain *before* or *after* LUT).
