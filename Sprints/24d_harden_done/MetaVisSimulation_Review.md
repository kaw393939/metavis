# MetaVisSimulation Code Review

**Date:** 2025-12-21
**Reviewer:** Antigravity Agent
**Module:** `MetaVisSimulation`

## 1. Executive Summary

`MetaVisSimulation` is the engine room of the application. It contains the **Production Renderer** (`MetalSimulationEngine`), the **Clip Loader** (`ClipReader`), and the **Graph Compiler** (`TimelineCompiler`).

**Strengths:**
- **Separation of Concerns:** `TimelineCompiler` strictly separates the editing model (Time, Clips, Tracks) from the execution model (Nodes, Textures, Shaders). This allows the renderer to be stateless and optimized.
- **Robust Fallbacks:** `MetalSimulationEngine` has an elaborate fallback mechanism. It tries to load a pre-compiled `default.metallib`. If that fails or is missing kernels, it compiles shaders from *hardcoded strings* embedded in the binary. This is excellent for development robustness.
- **Color Management:** The compiler enforces an "ACEScg Golden Thread". All inputs (video, images, procedural) are converted to ACEScg via IDT nodes before compositing, ensuring correct blending math.

**Critical Gaps:**
- **Shell-Out Decoding:** `FFmpegEXRDecoder` uses `Process()` to call `ffmpeg` CLI for **EXR** stills. This is slow, fragile, and not suitable for a shipping app (sandbox restrictions, dependency management).
- **Hardcoded Shaders:** While useful for dev, the "Hardcoded Sources" path in `MetalSimulationEngine` should be a last resort. Production builds should strictly enforce the presence of a validated `metallib`.
- **Memory Management:** `ClipReader` has a bounded frame cache (`maxCachedFrames`) but also maintains unbounded caches (`stillPixelBuffers`, `decoders`). For long sessions / many assets, memory can grow without a pressure-release valve.

---

## 2. Detailed Findings

### 2.1 The Renderer (`MetalSimulationEngine.swift`)
- **Actor:** Thread-safe execution.
- **Texture Pooling:** Uses a `TexturePool` to reuse intermediate textures, critical for GPU memory performance.
- **Watermarking:** Built-in compute shader support for trial-mode watermarks.
- **Debug Logging:** Writes to `/tmp/metavis_engine_debug.log`, handy for deep debugging but should likely be OsLog in production.

### 2.2 The Compiler (`TimelineCompiler.swift`)
- **Clip Sorting:** Deterministically sorts clips (by time, then ID) before compositing to avoid z-fighting flicker.
- **Node Generation:** Automatically inserts:
    1.  `source_texture` (or procedural generator)
    2.  `idt_...` (Input Device Transform)
    3.  Effects chain
    4.  Compositor
    5.  `odt_...` (Output Device Transform to Rec.709)

### 2.3 Media Loading (`ClipReader.swift`)
- **AVFoundation:** Uses `AVAssetReader` for video.
- **FFmpeg:** Used for EXR still decode only.
- **Timing Normalization:** Contains logic to detect Variable Frame Rate (VFR) and quantize it to Constant Frame Rate (CFR), preventing A/V drift.

---

## 3. Recommendations

1.  **Internalize EXR Decoding:** Replace the `ffmpeg` shell-out with a native Swift/C library (e.g. `tinyexr` or `ImageIO` if supported) to remove the external dependency and improve performance.
2.  **Resource Bundle Strictness:** Add a "Production Mode" flag that disables the hardcoded shader fallback and crashes if the `metallib` is missing, ensuring we don't accidentally ship dev shaders.
3.  **Memory Pressure:** Implement `OSMemoryNotification` handling in `ClipReader` to flush the cache on memory warnings.
