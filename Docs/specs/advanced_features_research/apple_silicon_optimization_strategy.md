# Apple Silicon Optimization Strategy: M3 & Beyond
**Date:** 2025-12-20

## 1. Executive Summary
To achieve "Masterpiece" performance on Apple Silicon (M3/M4), we must move beyond standard Metal/Swift. We will leverage **Mesh Shaders** for particles, **ANE** for local intelligence, and **Accelerate (AMX)** for deterministic math.

## 2. Technology Mapping

### A. Mesh Shaders (M3+)
*   **Target Sprint:** Sprint 28 (Fluid Dynamics)
*   **Concept:** Traditional particle systems use Vertex/Fragment shaders. M3 introduces **Mesh Shaders**, allowing massive geometry generation (culling, LOD) entirely on GPU.
*   **Optimization:** Implement the Fluid Emitter using a `Object Mesh Shader` stage that expands particles into optimized quads/meshes based on density, skipping invisible clusters.
*   **Legacy Fallback:** Provide a standard Compute->Vertex path for M1/M2.

### B. Neural Engine (ANE) & CoreML
*   **Target Sprint:** Sprint 32 (Neuro-Symbolic)
*   **Concept:** The ANE is specialized for Matrix Multiplication but has strict shape requirements (multiples of 16, channel-last).
*   **Optimization:**
    *   **Quantization:** Use `coremltools` to bake the Llama-3 model as **Int8** or **Int4** to fit in RAM and maximize ANE throughput.
    *   **Split Softmax:** Manually implement Softmax as a split operation if profiling shows ANE stalls (common in Transformers).
    *   **KV Caching:** Implement a stateful KV-Cache using `IOSurface` to avoid copying memory between CPU and ANE for every token generation.

### C. AMX (Apple Matrix Co-processor) via Accelerate
*   **Target Sprint:** Sprint 26 (PBR) & Sprint 29 (VFX)
*   **Concept:** AMX is accessed via `Accelerate.framework`.
*   **Optimization:**
    *   **Bloom/Blur:** Use `vImage` convolution functions for the CPU-side fallback or pre-processing, which automatically use AMX.
    *   **Linear Algebra:** If implementing CPU-side physics (Sprint 30), use `vDSP` for SIMD operations instead of raw loops. Note: FxPoint is integer-based, so AMX (Float) applies less there, but NEON SIMD is applicable.

### D. Dynamic Caching (M3)
*   **Target Sprint:** All Rendering Sprints (26, 28, 29)
*   **Concept:** M3 dynamically allocates local GPU memory.
*   **Action:** Ensure our `MetalSimulationEngine` uses `.memoryless` attachment descriptors for all intermediate render targets (Depth, Albedo, Normal). This allows the hardware to keep these in on-chip tile memory, leveraging Dynamic Caching implicitly.

### E. Advanced I/O (Storage)
*   **Target Sprint:** Sprint 25 (Ingest) & Sprint 29 (Delivery)
*   **Concept:** Reading 8K video can thrash the OS Page Cache.
*   **Optimization:**
    *   **Streaming:** Use `DispatchIO` (GCD) with `F_NOCACHE` file flag for sequential reading (Ingest/Analysis). This prevents "file cache pollution" from evicting UI assets.
    *   **Seeking:** Use `pread` on a concurrent queue for random access.
    *   **Export:** Use `AVAssetWriter` but ensure inputs are fed via a `DispatchData` pipe to minimize copying.

### F. Low-Latency Audio (Audio Engine)
*   **Target Sprint:** Sprint 21 (Sync) & Sprint 24 (Fusion)
*   **Concept:** `AVAudioEngine` can glitch if ARC triggers on the render thread.
*   **Optimization:**
    *   **Source:** Use `AVAudioSourceNode` with a `UnsafeMutableAudioBufferListPointer` ring buffer (lock-free) instead of `AVAudioPlayerNode` scheduling classes.
    *   **Offline:** For Sprint 30 (Determinism), explicitly switch the engine to `enableManualRenderingMode(.offline)`. This decouples the render clock from the hardware clock, allowing "faster than real-time" processing.

### G. Metal Ray Tracing (PBR)
*   **Target Sprint:** Sprint 26 (PBR)
*   **Optimization:**
    *   **Opaque Optimization:** Explicitly call `setOpaqueTriangleIntersectionFunction` to bypass "Any Hit" shaders for opaque materials (most of our PBR objects). This doubles traversal speed on M3.

## 3. Implementation Directives

1.  **Refine Sprint 28 (Fluids):** Add "Mesh Shader Path" for M3 devices.
2.  **Refine Sprint 32 (Neuro-Sym):** Mandate "Int8 Quantization" and "KV-Cache IOSurface" in the deliverables.
3.  **Refine Sprint 26 (PBR):** Ensure `PBR.metal` uses standard `half` precision to allow A17/M3 ALU double-rate execution.

## 4. Glossary
*   **AMX:** Apple Matrix Co-processor (hidden, used by Accelerate).
*   **ANE:** Apple Neural Engine (AI accelerator).
*   **Mesh Shader:** New geometry pipeline (Object -> Mesh) replacing Vertex shaders.
*   **Dynamic Caching:** M3 hardware feature for register/tile memory.
