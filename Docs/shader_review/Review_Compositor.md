# Shader Review: Compositor.metal

**File**: `Sources/MetaVisGraphics/Resources/Compositor.metal`  
**Reviewer**: Antigravity  
**Target Hardware**: Apple Silicon M3 (Metal 3)  
**Context**: Multi-track Video Compositing

## Overview
Handles blending of multiple video layers (Alpha Blend, Crossfade, Swipe/Wipe).

## Apple Silicon M3 Optimizations

### 1. Tile Memory & Imageblocks (CRITICAL)
*   **Current**: `compositor_multi_layer` reads from `texture2d_array`, composites in a register `float4`, then writes to global memory.
    ```cpp
    for (uint i=0; i < layerCount; i++) { ... }
    output.write(result, gid);
    ```
*   **Problem**: This approach creates high bandwidth if we have many layers, though the current loop is decent (reads layers, accumulates in register, writes once).
*   **Optimization (Tile Shaders)**:
    *   If we switch to a **Render Pipeline** (Rasterization), we can use **Programmable Blending**.
    *   We draw a full-screen quad for *each clip*.
    *   The GPU keeps the destination pixel in **Tile Memory** (L1/SRAM on GPU).
    *   We blend into Tile Memory.
    *   We flush to RAM only once at the end of the frame.
    *   *Benefit*: Massive bandwidth reduction for complex timelines (10+ layers).
    *   *M3 Support*: M3 supports `memoryless` targets perfect for this.

### 2. Bandwidth Compression
*   **Recommendation**: Ensure all source textures (video frames) are created with `MTLTextureUsagePixelFormatView` if re-viewing formats, but importantly verify `storageMode`. 
*   **Unified Memory**: `storageModeShared` is usually best for CVMetalTextureCache (Zero Copy). `storageModePrivate` is faster for intermediate compositions. The engine seems to handle `private` with staging copies, which is good.

### 3. Branchless Logic
*   **Current**: `compositor_dip` uses `if (t < 0.5f)`.
    ```cpp
    if (t < 0.5f) { ... } else { ... }
    ```
*   **Fix**:
    ```cpp
    float u1 = t * 2.0;
    float u2 = (t - 0.5) * 2.0;
    float4 res1 = mix(colorA, c, u1);
    float4 res2 = mix(c, colorB, u2);
    // Select without branching logic (though compiler might optimize this simple if)
    result = (t < 0.5) ? res1 : res2; 
    ```

### 4. Wipe Logic
*   **Current**: `switch (dir)` inside the kernel for every pixel.
    ```cpp
    switch (dir) { case 0: ... }
    ```
*   **Optimization**: Since `dir` is uniform for the whole dispatch, this branching is coherent (all threads take same path). However, it adds register pressure.
*   **Fix**: Pass a `float2 direction_vector` and a `bool invert` instead of an integer enum. Calculate dot product or simple comparison.

## Usage in Simulation
*   **Pipeline**: `compositor_multi_layer` is key for the main timeline.
*   **Gaps**: Currently `MetalSimulationEngine.swift` seems to dispatch `encodeNode` sequentially. It doesn't seem to use `compositor_multi_layer` widely yet (seems to use discrete `alpha_blend` nodes?). Actually, the kernel list in `MetalSimulationEngine` includes `compositor_multi_layer`, but usage needs verification in `Renderer`.

## Action Plan
- [ ] Evaluate switching Compositor to **Raster Pipeline** (Render Encoder) to utilize hardware blending and Tile Memory.
- [ ] Refactor `wipe` and `dip` to use math-based transitions instead of `if/switch`.
