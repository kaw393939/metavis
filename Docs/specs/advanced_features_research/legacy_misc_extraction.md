# Legacy Miscellaneous Extraction Report

**Date:** 2025-12-20
**Scope:** `metavis1` (Procedural), `metavis2` (Video), `metavis4` (Scheduler)
**Status:** COMPLETE

## 1. Executive Summary
This final report covers the remaining "Hidden Gems" of the legacy codebase: the high-performance **Video Pipeline**, the persistent **Job Scheduler**, and the advanced **Procedural Art** engines.

## 2. Feature Deep Dive

### A. Professional Video Pipeline
**Source:** `metavis2/.../Video/VideoDecoder.swift` & `VideoCompositingPipeline.swift`
**Key Capabilities:**
*   **Zero-Copy Decoding:** Uses `CVMetalTextureCache` to decode frames directly into Metal textures, bypassing CPU memory copies.
*   **HDR Support:** explicit handling of `kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange` (10-bit HEVC) with a custom Compute Shader conversion to linear `rgba16Float`.
*   **Decode-Ahead:** Implements an async buffer to pre-decode frames, ensuring the GPU never waits for the disk.
*   **Compositor:** Supports "Behind Subject" blending using Vision framework segmentation.

### B. Persistent Job Queue
**Source:** `metavis4/.../Core/JobQueue.swift`
**Backing:** SQLite (GRDB)
**Key Capabilities:**
*   **Dependency Management:** Jobs can depend on other jobs (DAG structure).
*   **Persistence:** Jobs survive app restarts.
*   **Priority:** Explicit priority field for ordering.

### C. Procedural Art Engine
**Source:** `metavis1/.../Procedural/FieldKernels.metal` & `Fractals.metal`
**Key Capabilities:**
*   **GPU Graph Interpreter:** A Compute Kernel (`fx_procedural_graph`) that executes a node graph *on the GPU*. It supports operations like `OP_PERLIN`, `OP_DOMAIN_WARP`, `OP_MIX`. This enables user-created procedural textures without compiling new shaders.
*   **Fractals:** Optimized renderers for Julia, Mandelbrot, and Burning Ship sets.
*   **Fire Shader:** A customized FBM implementation for realistic fire/energy effects.

### D. Virtual Camera
**Source:** `metavis3/.../VirtualCamera.swift`
**Key Capabilities:**
*   **Physical Sensor Sizes:** IMAX 70mm, Super35, Full Frame.
*   **Optics:** Focal Length, f-stop, computed FOV.

## 3. Integration Plan

### Phase 1: The "Eyes" (Sprint 02+)
1.  **Port `VideoDecoder`** to `MetaVisIngest`. The zero-copy logic is mandatory for performance.
2.  **Port `VideoCompositingPipeline`** to `MetaVisGraphics`.

### Phase 2: The "Brain" (Sprint 04+)
3.  **Port `JobQueue`** to `MetaVisCore`. The dependency management is perfect for our AI Agent tasks.

### Phase 3: The "Canvas" (Infinite)
4.  **Port `FieldKernels.metal`** to `MetaVisGraphics`. The Graph Interpreter is the foundation for a "Node Editor" feature for users.
