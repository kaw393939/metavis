# Research Note: Mining Legacy MetalVisCore

**Source Location:** `docs_backup/Sources_Old/MetalVisCore`

## 1. Executive Summary
A deep dive into the legacy codebase revealed highly sophisticated, production-grade rendering and math libraries that far exceed standard "starter kit" implementations. **Key discoveries include a complete GPU-accelerated Graph Layout engine, a broadcast-ready Swiss Grid system, and a "Superhuman" Color Space library.**

These components should be **ported immediately** to `MetaVisKit2` rather than rewritten.

## 2. High-Value Discoveries

### A. The "Golden" Standards (Must Port)

#### 1. `ColorSpace.metal` (`Shaders/`)
-   **What it is:** A comprehensive Single Source of Truth for color management.
-   **Capabilities:**
    -   **Gamuts:** ACEScg (AP1), AP0, Rec.2020, P3-D65, sRGB/Rec.709.
    -   **Transfer Functions:** sRGB, Gamma 2.4, PQ (ST.2084), HLG, Apple Log.
    -   **Chromatic Adaptation:** Bradford D65 <-> D60 transforms (Critical for ACES).
-   **Why it's vital:** It abstracts complex color science into `DecodeToACEScg()` and `EncodeFromACEScg()`. This ensures the entire pipeline speaks the same mathematical language.

#### 2. `SwissGrid.swift` (`Layout/`)
-   **What it is:** A 12-column broadcast grid computation engine.
-   **Capabilities:**
    -   Calculates "Safe Areas" (Title Safe / Action Safe).
    -   Handles 16:9, 4K, and 21:9 Cinema aspect ratios.
    -   Provides an 8pt baseline grid for vertical rhythm.
-   **Why it's vital:** This is the mathematical foundation for "Professional" UI layout. It differentiates MetaVis from generic tools.

#### 3. `PhysicalCamera.swift` (`Engine/Scene/`)
-   **What it is:** A photorealistic camera model.
-   **Key Math:**
    -   **FOV Calculation:** Derived from Sensor Width (mm) and Focal Length (mm).
    -   **Reverse-Z Projection:** Implements infinite far-plane projection matrix.
    -   **Lens Shift**: Implements Matrix Shear for Tilt-Shift and Depth of Field jittering.
-   **Why it's vital:** It aligns the 3D renderer with real-world cinematography concepts.

### B. Advanced Rendering Tech

#### 1. `SDFText` System (`Text/` & `Shaders/`)
-   **Components:** `SDFGenerator.swift` (CPU MSDF Gen) + `SDFText.metal` (GPU Rendering).
-   **Technique:** Uses Multi-channel Signed Distance Fields (MSDF) + Screen Space Derivatives (`dfdx`/`dfdy`) for sub-pixel anti-aliasing.
-   **Result:** Infinite zoom on text without pixelation.

#### 2. `VolumetricNebulaPass` (`Engine/Passes/`)
-   **Technique:** Raymarching though FBM density fields.
-   **Physics:** Implements Henyey-Greenstein phase function for anisotropic scattering.
-   **Usage:** The backend for the "Space" theme.

#### 3. `GraphLayout.metal` (`Shaders/`)
-   **Technique:** GPU-Accelerated Force Directed Layout using Barnes-Hut QuadTrees.
-   **Performance:** $O(N \log N)$ physics on thousands of nodes.
-   **Usage:** Overkill for simple timelines, but essential for complex Node Graphs involving hundreds of assets.

## 3. Integration Plan

1.  **Start `MetaVisGraphics`**: Create a new module to house these shared math/shader libraries.
    -   Move `ColorSpace.metal` to `MetaVisGraphics/Shaders`.
    -   Move `SwissGrid.swift` to `MetaVisGraphics/Layout`.
    -   Move `PhysicalCamera.swift` to `MetaVisGraphics/Scene`.

2.  **Shader Library Integration**:
    -   The `RenderWorker` in `MetaVisScheduler` should link against `MetaVisGraphics` for its color science.

3.  **UI Integration**:
    -   The `MetaVisStudio` UI should use `SwissGrid` for laying out the "Director's Workspace".

## 4. Conclusion
We have a "Ferrari engine" sitting in the garage. The legacy code is not "old" in terms of technique—it is state-of-the-art. We will integrate these components directly.
