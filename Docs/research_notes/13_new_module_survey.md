# New Module Survey: The "Device-Centric" Architecture

## Executive Summary
A survey of the `metavis_render_two` project root reveals a comprehensive set of existing modules that define a **Device-Centric** and **Service-Oriented** architecture. Unlike the legacy monolithic core, this new design abstracts all capabilities (Cameras, Lights, AI Generators) as `VirtualDevice`s managed by a central session.

## Module Breakdown

### 1. The I/O Layer (Hardware & Services)
*   **`MetaVisIngest`**: The "Input" layer.
    *   **Role**: Abstraction for physical hardware and import logic.
    *   **Key Concept**: `PhysicalCameraDevice` (connects to ARRI/RED), `GeneratorDevice` (connects to AI services).
*   **`MetaVisExport`**: The "Output" layer.
    *   **Role**: Final delivery.
    *   **Key Capabilities**: Standard Video Encoding + **Spatial Export (USDZ)** for Vision Pro.
*   **`MetaVisServices`**: The "Gateway".
    *   **Role**: A unified, type-safe API for Generative AI providers (Vertex AI, ElevenLabs, Veo).
    *   **Philosophy**: Provider-agnostic requests ("Generate Image" vs "Call Midjourney").

### 2. The Intelligence Layer (Eyes & Ears)
*   **`MetaVisPerception`**:
    *   **Role**: Computer Vision & Scene Understanding.
    *   **Components**: `PersonIntelligence` (Cast), `StyleIntelligence` (Look/Color), `SceneUnderstanding` (Depth/Saliency).
*   **`MetaVisImageGen`**:
    *   **Role**: Dedicated 2D generative pipeline (Textures, Storyboards).
*   **`MetaVisAudio`**:
    *   **Role**: Spatial Audio engine + Generative Voice (TTS).
    *   **Architecture**: Audio is treated as a 3D element in the "Virtual Set".

### 3. The Core System
*   **`MetaVisCore`**:
    *   **Role**: The Schema / Data Model.
    *   **Key Innovation**:
        *   **`VirtualDevice` Framework**: A protocol normalizing all controllable entities.
        *   **`SpatialContext`**: Replaces "Scene State". Models environment, location, and time to give AI context.
*   **`MetaVisKit`**:
    *   **Role**: The "Director's Viewfinder" (UI & Agent Interface).
    *   **Capabilities**: Defines the `AgentInterface` (MCP Tools) and `ViewportController`.

### 4. Utilities & Data
*   **`MetaVisValidation`**: Command-line executable for system integrity checks.
*   **`MetaVisLab`**: A data repository (not code) for Cataloging Look Assets, Reference Images, and Color Science experiments (`aces-core`, `colour-nuke`).
*   **`MetaVisCLI`**: Command-line interface for headless operation.
*   **`MetaVisCalibration`**: Test harness for physics/color calibration.

## Architectural Implications
The previously drafted `ARCHITECTURE.md` must be updated to reflect this specific **Device/Service** taxonomy. The system is not just a "Render Engine" but a "Virtual Production Studio" where:
1.  **Agents** act as Operators.
2.  **Devices** (Virtual & Physical) do the work.
3.  **Services** provide the Intelligence.
