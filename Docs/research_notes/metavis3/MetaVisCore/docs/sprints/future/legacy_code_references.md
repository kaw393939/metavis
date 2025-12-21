# MetaVisCore - Legacy Code References

This document tracks the shared data structures and utilities.

## Data Models
*   **`metavis_render/Sources/MetaVisRender/Data/RenderManifest.swift`**
    *   **Description**: The central DTO defining the scene, camera, and layers.
    *   **Key Features**: `Codable`, `Sendable`, `ManifestMetadata`, `SceneDefinition`.
    *   **Why it's valuable**: It is the "contract" between all modules.

*   **`metavis_render/Sources/MetaVisRender/Data/RenderJob.swift`**
    *   **Description**: Defines a unit of work for the renderer.

## Utilities
*   **`metavis_render/Sources/MetaVisRender/Core/TimelineClock.swift`**
    *   **Description**: High-precision timing logic.
    *   **Key Features**: `CMTime` wrappers, frame rate conversions.

*   **`metavis_render/Sources/MetaVisRender/Utils/`**
    *   **Description**: General purpose extensions and helpers.
