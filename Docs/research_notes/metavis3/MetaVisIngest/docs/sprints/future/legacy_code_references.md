# MetaVisIngest - Legacy Code References

This document tracks the media ingestion and analysis tools.

## Ingestion Logic
*   **`metavis_render/Sources/MetaVisRender/Ingestion/FootageIngestService.swift`**
    *   **Description**: Handles importing video files.
    *   **Key Features**: Proxy generation, metadata extraction.

*   **`metavis_render/Sources/MetaVisRender/Ingestion/MediaProbe.swift`**
    *   **Description**: Analyzes media files using AVFoundation.
    *   **Key Features**: Codec detection, frame rate verification, color space reading.

*   **`metavis_render/Sources/MetaVisRender/Ingestion/Index/`**
    *   **Description**: Database/Indexing logic for assets.
