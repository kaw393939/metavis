# MetaVisExport - Legacy Code References

This document tracks the media encoding and muxing logic.

## Video Encoding
*   **`metavis_render/Sources/MetaVisRender/Engine/Export/VideoExporter.swift`**
    *   **Description**: The primary video encoder interface.
    *   **Key Features**: Zero-copy Metal integration.

*   **`metavis_render/Sources/MetaVisRender/Engine/Export/VideoToolboxEncoder.swift`**
    *   **Description**: Low-level VideoToolbox wrapper.
    *   **Key Features**: Hardware acceleration, HEVC/ProRes support.

## Audio Encoding
*   **`metavis_render/Sources/MetaVisRender/Audio/Export/`**
    *   **Description**: Audio encoding logic (AAC/PCM).
