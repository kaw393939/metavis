# Legacy Autopsy — Apple Silicon Optimizations (metavis1 / metavis2)

## Scope
This note harvests **performance patterns worth porting into MetaVisKit2** from legacy `metavis1` and `metavis2`, with an emphasis on Apple Silicon (M‑series) characteristics:
- GPU tile memory (`.memoryless` render targets)
- heap-backed texture reuse (`MTLHeap`)
- avoiding CPU↔GPU roundtrips (zero-copy / shared-event sync)
- predictable throughput (bounded in-flight frames + budgets)

Legacy roots (high-signal):
- metavis2:
  - `Docs/research_notes/metavis2/Sources/MetaVisRender/Engine/TexturePool.swift`
  - `Docs/research_notes/metavis2/Sources/MetaVisRender/Engine/Export/VideoExporter.swift`
  - `Docs/research_notes/metavis2/Sources/MetaVisRender/Performance/{DeviceProfile,PerformanceConfig,PerformanceMonitor}.swift`
  - `Docs/research_notes/metavis2/Sources/MetaVisRender/Core/{AsyncComputeManager,AMXColorTransform}.swift`
  - Passes: `.../Engine/Passes/{BloomPass,ToneMapPass,CinematicLookPass}.swift`
  - Export processing: `.../Export/Processing/FrameProcessor.swift`
- metavis1:
  - `Docs/research_notes/metavis1/Sources/MetalVisCore/Engine/Graph/TexturePool.swift`
  - `Docs/research_notes/metavis1/Sources/MetalVisCore/Engine/Passes/GeometryPass.swift`
  - `Docs/research_notes/metavis1/Sources/MetalVisCore/Text/SDFGenerator.swift`

---

## TL;DR (what’s worth porting)
1) **Heap-backed intermediate allocation** (`MTLHeap` + LRU + budgets) + **memoryless render targets** for transient passes.
2) **Threadgroup sizing + non-uniform dispatch** patterns in compute passes.
3) **Export pipeline**: bounded in-flight frames, **shared-event GPU sync**, and a real **zero-copy path** (avoid `getBytes`).
4) **Adaptive performance layer**: device profiling → performance config presets → monitoring (thermal/memory pressure) → throttling.
5) Targeted CPU acceleration patterns: **AMX-friendly SIMD dot** transforms, Accelerate/vDSP where relevant, and structured parallelism.

---

## A) GPU memory + allocation

### 1) `MTLHeap`-backed `TexturePool` (metavis2)
What it is:
- A pool that allocates textures from one or more `MTLHeap`s and reuses them across frames.
- Adds **memory budget tracking** and **LRU eviction**.
- Supports **transient `.memoryless` textures** for render targets that never need to be sampled later.
- Tracks hazards/usage so reuse is safe.

Why it matters:
- Reduces per-frame `MTLTexture` creation (CPU overhead + driver churn).
- Controls VRAM growth via budgets, making performance more predictable.
- `.memoryless` avoids round-tripping tile memory to system memory on tile-based Apple GPUs.

Porting guidance to MetaVisKit2:
- Provide a single abstraction used by the multi-pass engine to allocate named intermediates:
  - `acquireIntermediate(descriptor:usage:)` (private/heap)
  - `acquireTransientRenderTarget(...)` (memoryless when possible)
  - `release(...)` / `endFrame()` to return textures to pool and advance LRU
- Treat deterministic behavior as an invariant: allocation decisions must not depend on wall-clock time.

Pitfalls:
- `.memoryless` is only valid for render targets and cannot be sampled later. Use it only for depth/stencil or passes that resolve immediately.
- Hazard tracking and command-buffer lifetimes matter; reusing a texture before the GPU is done will cause corruption.

Legacy evidence:
- `Docs/research_notes/metavis2/Sources/MetaVisRender/Engine/TexturePool.swift`
- `Docs/research_notes/metavis1/Sources/MetalVisCore/Engine/Graph/TexturePool.swift` (simpler pool + “clear using same command buffer” correctness invariant)

### 2) Explicit `.memoryless` depth usage (metavis1)
- Uses `.memoryless` for depth textures when the GPU family supports it; otherwise `.private`.

Legacy evidence:
- `Docs/research_notes/metavis1/Sources/MetalVisCore/Engine/Passes/GeometryPass.swift`

---

## B) GPU compute scheduling + kernels

### 1) Threadgroup sizing derived from pipeline properties
Pattern:
- Use `threadExecutionWidth` and `maxTotalThreadsPerThreadgroup` to choose a reasonable 2D threadgroup.
- Prefer `dispatchThreads` (non-uniform) to avoid over-dispatch.

Legacy evidence:
- `Docs/research_notes/metavis2/Sources/MetaVisRender/Engine/Passes/BloomPass.swift`
- `Docs/research_notes/metavis2/Sources/MetaVisRender/Engine/Passes/ToneMapPass.swift`

Porting guidance:
- Centralize a helper: `optimalThreadgroupSize(pipelineState:)` (deterministic, no device queries beyond pipeline state).

### 2) MPS as a pragmatic “fast path” building block
Pattern:
- Use MPS for blur/scale and other common image ops when it’s a net win.

Legacy evidence:
- `Docs/research_notes/metavis2/Sources/MetaVisRender/Engine/Passes/CinematicLookPass.swift` (MPS blur components)
- `Docs/research_notes/metavis2/Sources/MetaVisRender/Export/Processing/FrameProcessor.swift` (MPS scaling)
- `Docs/research_notes/metavis1/Sources/MetalVisCore/Renderer/MetalRenderer.swift` (MPS resize)

Caveat:
- Treat MPS usage as “implementation detail” under deterministic pass semantics; avoid implicit, hidden state.

---

## C) Export pipeline (throughput + quality)

### 1) Bounded in-flight frames
Pattern:
- Use a semaphore (or equivalent) to cap frames in flight, preventing unbounded memory growth during export.

### 2) Prefer GPU-GPU synchronization where possible
Pattern:
- Use `MTLSharedEvent`-style synchronization to coordinate GPU work without blocking the CPU.

### 3) Avoid `getBytes` for the hot path
Observation:
- Parts of the legacy exporter still fall back to `texture.getBytes(...)` (CPU readback). This is a major throughput killer and can also be wrong if format conversion is needed.

Legacy evidence:
- `Docs/research_notes/metavis2/Sources/MetaVisRender/Engine/Export/VideoExporter.swift`

Porting guidance:
- Aim for a strict policy:
  - Render output stays in GPU memory.
  - Convert to encoder-friendly pixel formats via GPU (compute/blit) into a `CVPixelBuffer` backed by an `IOSurface` (zero-copy).
  - Append via `AVAssetWriterInputPixelBufferAdaptor`.

Test guidance:
- Add an export perf test that fails if the exporter path uses CPU readback for standard formats.

---

## D) Adaptive performance (capabilities → config → monitoring)

### 1) Device profile and presets
Pattern:
- Maintain a capability model (chip family / estimated GPU/ANE capacity) and choose a config preset.

Legacy evidence:
- `Docs/research_notes/metavis2/Sources/MetaVisRender/Performance/DeviceProfile.swift`
- `Docs/research_notes/metavis2/Sources/MetaVisRender/Performance/PerformanceConfig.swift`

### 2) Monitoring + throttling loop
Pattern:
- Periodically sample thermal state and memory pressure, expose snapshots, and feed back into throttling.

Legacy evidence:
- `Docs/research_notes/metavis2/Sources/MetaVisRender/Performance/PerformanceMonitor.swift`

Porting guidance to MetaVisKit2:
- Hang this off `RenderDevice` (Sprint 02): capabilities + recommended budgets + current pressure signal.

---

## E) CPU-side acceleration patterns

### 1) AMX-friendly batch transforms (metavis2)
Pattern:
- Batch color transforms as vector dot products over large buffers (compiler can map to AMX-like execution on Apple Silicon).
- Maintain scalar fallbacks for correctness testing.

Legacy evidence:
- `Docs/research_notes/metavis2/Sources/MetaVisRender/Core/AMXColorTransform.swift`

### 2) Structured parallelism for heavy CPU work (metavis1)
Pattern:
- `DispatchQueue.concurrentPerform` for embarrassingly parallel generation (e.g., SDF/MSDF).

Legacy evidence:
- `Docs/research_notes/metavis1/Sources/MetalVisCore/Text/SDFGenerator.swift`

---

## Recommended MetaVisKit2 backlog (actionable)

### High priority (direct wins)
- Add a `TexturePool` abstraction for deterministic multi-pass intermediates:
  - heap-backed reuse (`MTLHeap`) + LRU + budgets
  - support `.memoryless` transient render targets
- Export: implement a real GPU→`CVPixelBuffer` zero-copy path; remove CPU readback from the default path.
- Add perf budgets to Sprint 11:
  - render frame throughput (ms) and memory high-water (MB)
  - export throughput (fps) with a cap on in-flight frames

### Medium priority (quality of life + predictability)
- Centralize threadgroup sizing utilities + adopt non-uniform `dispatchThreads` for compute passes.
- Adopt a device/performance config model (capabilities + presets) hanging off `RenderDevice`.
- Add a lightweight performance monitor (thermal/memory pressure) to enable future throttling.

### Later / opportunistic
- Port AMX-friendly color transform utilities into `MetaVisCore`/`MetaVisGraphics` for LUT/color pipeline hot spots.
- Use MPS selectively for blur/scale, under deterministic pass orchestration.

---

## Suggested tests / benchmarks (ties into Sprint 11)
- **Determinism:** golden-frame hashes for pure render paths (already planned).
- **Perf:** `XCTest.measure` budgets:
  - single-frame render at fixed res
  - N-frame export at fixed settings
- **Allocations:** assert “no per-frame texture allocations” for steady-state multi-pass runs (instrument pool counters).
- **Exporter correctness:** pixel-format conversion correctness test (RGBA16F → encoder format) with deterministic generated patterns.
