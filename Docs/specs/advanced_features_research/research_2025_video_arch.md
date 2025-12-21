# 2025 Companion Research: Video & Architecture

**Date:** 2025-12-20
**Scope:** Zero-Copy Video, Copy-Free Architecture, Unified Memory
**Status:** COMPLETE

## 1. Executive Summary
The architecture of 2025 is defined by "Zero-Copy." With Unified Memory, moving data is the bottleneck, not processing it.

## 2. Zero-Copy Video Pipeline
**Legacy:** `CVPixelBuffer` -> `CVMetalTextureCache`.
**2025 State of the Art:**
*   **Remains the Gold Standard:** `CVMetalTextureCache` is still the only way to alias a VideoToolbox buffer as a Metal Texture.
*   **10-bit HDR:** Handling `kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange` is mandatory. The conversion must happen in a Compute Shader (as implemented in legacy) because standard blit commands often clamp or color-shift.
*   **Recommendation:** Keep the legacy `VideoDecoder` but verify the YUV->RGB colorspace matrix (Rec.2020) is perfect.

## 3. Unified Memory Optimization
**Legacy:** Managed pointers.
**2025 State of the Art:**
*   **Memoryless Render Targets:** On Tile-Based Deferred Renderers (M-series), use `.memoryless` for depth/stencil and MSAA resolve targets. They never leave on-chip tile memory.
*   **Resource Heaps:** Allocate all textures from a single `MTLHeap` to avoid allocation overhead and memory fragmentation.
*   **Native Tensors (Metal 4):** Watch for "Native Tensors" in Metal 4 (2025) to unify ML and Graphics memory.

## 4. Task Graphs & Scheduling
**Legacy:** GCD.
**2025 State of the Art:**
*   **Structured Concurrency (Swift 6):** `TaskGroup` and `async let` are the standard. GCD `DispatchQueue` is legacy code.
*   **OSAllocatedUnfairLock:** The fastest primitive for protecting shared state (replaces `NSLock`).
*   **Recommendation:** Rewrite `JobQueue` (SQLite) to use **Swift Concurrency** and `OSAllocatedUnfairLock`.

## 5. Implementation Recommendations
1.  **Verify Color Math:** YUV->RGB conversion for HDR must use the correct matrix (Rec.2020 PQ).
2.  **Memoryless:** Ensure all intermediate render targets (Depth, G-Buffer ALBEDO) are `.memoryless`.
3.  **Swift 6 Migration:** Port all threading to Structured Concurrency.
