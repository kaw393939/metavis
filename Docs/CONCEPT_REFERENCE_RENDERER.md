# Concept: The Reference ACEScg Renderer ("The God Renderer")

> **Mission**: To be the unassailable Source of Truth for Color and Pixel Integrity.

## 1. The Core Philosophy: "Semper Veritas" (Always Truth)
This renderer is not designed for speed. It is designed for **correctness**.
*   **Internal Pipeline**: 100% `rgba16Float` (Half-Float) linear hierarchy.
*   **Mathematically Perfect**: No approximations. Use full analytical anti-aliasing where possible.

## 2. The Universal Interchange: OpenEXR
To allow "Project Chaining" (Project A feeds Project B), we cannot use video codecs (ProRes/HEVC) which are lossy and baked. We must use **OpenEXR**.

### The "Chaining" Workflow
1.  **Project A (Background Generation)**:
    *   Generates a Sci-Fi City.
    *   Export: `City_Background.exr` sequence (ACEScg Linear).
2.  **Project B (Compositing)**:
    *   Imports `City_Background.exr`.
    *   Overlays live actors.
    *   Renders Final Output.

**Requirement**: The Renderer must treat `.exr` sequences as a first-class "Video Stream".

## 3. Resolution Independence
The Renderer ignores "Screen Size". It thinks in "Canvas Space".
*   **Vector First**: All layout (`SwissGrid`) is calculated in normalized coordinates.
*   **Raster Second**: Only at the moment of capture do we ask "How many pixels?"
*   **Aspect Ratio Agnostic**: Setup for 9:16 (TikTok) or 2.39:1 (Cinema) is just a view matrix change.

## 4. The Extensible Interface (`SimulationEngineProtocol`)
To ensure this "God Renderer" can be swapped or upgraded, we define a strict interface.

```swift
protocol SimulationEngineProtocol {
    /// Configure the canvas (Resolution, Aspect, Color Space)
    func configure(config: RenderConfig) async throws
    
    /// Receive a graph of signals (Video, Audio, Effects) at time T
    func consume(frame: RenderFrame) async throws
    
    /// Produce the result
    /// - Returns: A Texture (live) or Data (export)
    func output() async throws -> RenderResult
}
```

## 5. Legacy Code Leverage
We already have the "Holy Grail" bits in our legacy mining:
*   `ColorSpace.metal`: Contains the verified ACEScg transforms.
*   `SimulationEngine.swift`: Contains the `CVMetalTextureCache` logic.

We will **transplant** these into the new `ReferenceRenderDevice`, stripping away the old app logic and keeping the math.
