# MetaVisSimulation - Legacy Code References

This document tracks the legacy rendering and export tools that must be ported to the new Cleanroom engine.

## Export Pipeline (Zero-Copy)
*   **`metavis_render/Sources/MetaVisRender/Engine/Export/VideoExporter.swift`**
    *   **Description**: The production-grade video encoder.
    *   **Key Features**:
        *   **Zero-Copy**: Uses `kCVPixelBufferMetalCompatibilityKey: true` and `kCVPixelBufferIOSurfacePropertiesKey` to allow Metal to write directly to encoder memory.
        *   **HEVC 10-bit**: Explicitly requests `kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange` for HDR export.
        *   **ProRes**: Supports ProRes 422 HQ and 4444.
    *   **Why it's valuable**: Enables high-performance, professional-quality output without CPU bottlenecks.

## Cinematic Effects
*   **`metavis_render/Sources/MetaVisRender/Engine/Passes/CinematicLookPass.swift`**
    *   **Description**: The unified post-processing stack.
    *   **Key Features**:
        *   **Physically Correct Order**: Lens Distortion -> Face Enhance -> Bloom -> Halation -> Anamorphic -> Grain.
        *   **Uniforms**: Specific structs for `HalationCompositeUniforms`, `FilmGrainUniforms`, `VignetteParams`, `LensSystemParams`.
    *   **Why it's valuable**: Gives the raw 3D output the "film look".

*   **`metavis_render/Sources/MetaVisRender/Engine/Passes/BloomPass.swift`**
    *   **Description**: Physically based bloom.
    *   **Key Features**: Downsample/Upsample pyramid for natural light bleed.

## Text & Graph
*   **`metavis_render/Sources/MetaVisRender/Text/GlyphManager.swift`**
    *   **Description**: SDF (Signed Distance Field) text engine.
    *   **Key Features**: Infinite resolution text rendering.

*   **`metavis_render/Sources/MetaVisRender/Engine/Graph/GraphPipeline.swift`**
    *   **Description**: The node-based compositing engine.
    *   **Key Features**: Allows flexible wiring of effects.
