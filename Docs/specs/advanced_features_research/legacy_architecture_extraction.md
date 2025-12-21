# Legacy System Architecture Report

**Date:** 2025-12-20
**Scope:** `metavis2` (Engine, Animation, Memory)
**Status:** COMPLETE

## 1. Executive Summary
This report details the high-performance architecture of the legacy `MetaVisRender` engine. It was designed for **low-latency** and **Apple Silicon optimization**.

## 2. Architecture Deep Dive

### A. The Render Engine
**Source:** `metavis2/.../Engine/RenderEngine.swift`
**Model:** Multi-buffered Producer/Consumer
**Key Capabilities:**
*   **In-Flight Throttling:** Uses a `DispatchSemaphore` to limit `maxInflightBuffers` (default 3, 4 for "High Performance"). This prevents the CPU from overrunning the GPU.
*   **Async Submission:** Command buffers are enqueued asynchronously.
*   **Pre-Warming:** Explicitly pre-warms Font Glyphs before rendering text-heavy manifests to avoid stutter.
*   **Abstraction:** Supports `View`, `Texture`, and `Offscreen` targets uniformly.

### B. Texture Memory Management
**Source:** `metavis2/.../Engine/TexturePool.swift`
**Model:** Heaped Recycling Pool
**Key Capabilities:**
*   **MTLHeap:** Uses `MTLHeap` to allocate memory. This allows texture aliasing (reusing the same physical memory for different texture objects), significantly reducing allocation overhead.
*   **Memoryless Textures:** Explicitly supports `.memoryless` storage mode for transient render targets (depth/stencil) that never leave the GPU tile memory. This is a massive bandwidth saver on Apple Silicon.
*   **LRU Eviction:** Enforces a strict memory budget (default 512MB, up to 1GB for editing) using a Least-Recently-Used eviction policy.

### C. Client-Side Animation
**Source:** `metavis2/.../Animation/TextAnimation.swift`
**Model:** Stateless Evaluation
**Key Capabilities:**
*   **Presets:** Huge library of cinematic effects: `StarWarsCrawl`, `Glitch`, `Typewriter`, `LowerThird`.
*   **Stateless:** `TextAnimationEvaluator.evaluate(...)` takes a time `t` and returns a pure struct `State` (opacity, offset, scale, blur). This makes the system perfectly deterministic and seekable (scrubbing works instantly).

## 3. Integration Plan

### Phase 1: Core Engine (Sprint 02+)
1.  **Port `TexturePool.swift`** immediately. It is generic and robust.
    *   *Upgrade:* Ensure it handles `MTLHeap` correctly on M3 chips (check `device.supportsFamily`).
2.  **Port `RenderEngine.config`** structure to `MetaVisRendering`.

### Phase 2: Animation Support (Sprint 05+)
3.  **Port `TextAnimation.swift`** to `MetaVisTimeline` or `MetaVisGraphics`. It defines the *logic* of movement.

### Phase 3: The "Director" (Sprint 10+)
4.  **Re-implement Pre-warming.** The `prewarm` function in `RenderEngine` is critical for smooth playback of text-heavy scenes.
