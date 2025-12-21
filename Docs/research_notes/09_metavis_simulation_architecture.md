# Research Note: MetaVisSimulation Architecture

**Source Documents:**
- `MetaVisSimulation/Engine/SimulationEngine.swift`
- `MetaVisSimulation/Video/VideoFrameProvider.swift`
- `MetaVisSimulation/Resources/Shaders.metal`

## 1. Executive Summary
`MetaVisSimulation` is the high-performance **Rendering Core**. It is a Metal-based engine designed for:
1.  **Zero-Copy Video**: Decoding direct to GPU (`CVMetalTextureCache`).
2.  **ACES Color Management**: All processing in 16-bit Linear Float (`rgba16Float`).
3.  **Hybrid Pipeline**: Combines Rasterization (Quads/Text) with Compute (FITS/Effects).

## 2. Core Components

### A. `SimulationEngine` (The Orchestrator)
-   **Responsibility**: Manages the Metal Device, CommandQueue, and Render Loop.
-   **Pipeline States**: Pre-compiled pipelines for Video, Color Grading, Split Screen, and ODT.
-   **Shader Compilation**: Dynamically concatenates generic Metal files to build a massive `simLibrary` at runtime. *Suggestion: Move this to build-time compilation for speed.*

### B. `VideoFrameProvider` (The Decoder)
-   **Architecture**: Uses `AVAssetReader` + `AVAssetReaderTrackOutput` (kCVPixelFormatType_64RGBAHalf).
-   **Optimization**: `CVMetalTextureCache` eliminates CPU-to-GPU copy.
-   **Color Handling**: Applies IDT (Input Device Transform) immediately upon decode to convert to ACEScg.

### C. Shaders (The Logic)
-   **Structure**: Modular headers (`ColorSpace.metal`, `PostProcessing.metal`).
-   **FITS Support**: Native kernels for scientific data normalization (`fitsToneMap`, `fitsComposite`).

## 3. Key Findings & Decisions
1.  **Zero-Copy Verification**: The code explicitly uses `CVMetalTextureCacheCreateTextureFromImage`. This is the "Golden Path" for performance.
2.  **Color Space**: The engine strictly enforces `rgba16Float` (Linear) for intermediate textures. `bgra8Unorm` is only used for the final ODT swapchain presentation.
3.  **FITS Integration**: Deep integration for astronomical data, treating it as a first-class citizen alongside video.

## 4. Synthesis for MetaVisKit2
-   **Adoption**: Adopt `MetaVisSimulation` as the core `RenderEngine`.
-   **Refinement**: 
    -   Extract `VideoFrameProvider` logic into a reusable `VideoDecoder` actor.
    -   Formalize the `RenderPass` struct to be the standard instruction set passed from `TimelineGraphBuilder`.
