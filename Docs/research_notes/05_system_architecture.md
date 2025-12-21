# Research Note: System Architecture & Gaps

**Source Documents:**
- `01_unified_core/ARCHITECTURE.md`
- `SYSTEM_OPERATION_AND_DEBUGGING.md`
- `GAP_ANALYSIS.md`

## 1. Executive Summary
MetaVis is architected as a **stateless rendering engine** driven by a **Resolver** pattern that compiles "Creative Intent" (JSON) into "Physical Reality" (Metal Command Buffers). While the rendering core is robust, the system lacks a stateful Application Model to handle project management, undo/redo, and interactive editing.

## 2. Core Architecture: The "Stateless" Engine
-   **RenderEngine:** A stateless executor. It takes a `RenderJob` (Manifest + Time Range + Output Target) and produces pixels. It has *no concept* of a "Project" or "Timeline".
-   **Resolvers:** The "Compiler" layer.
    -   `ManifestResolver`: Coordinates the compilation.
    -   `MaterialResolver`: JSON materials -> Metal structs.
    -   `PresetResolver`: Synthetic sugar ("studio_lighting" -> 3-point light setup).
-   **Zero-Copy Philosophy:**
    -   Video Decoder (Metal Texture Cache) -> Compositor (Metal) -> Encoder (VideoToolbox).
    -   Host memory (CPU) is rarely touched.

## 3. The Gap: Editing Logic
The current system generates video well but fails as an editor.
-   **Missing:**
    -   **Project State:** No "Open Project", "Save Project".
    -   **Mutation API:** No way to "Move clip A to 5:00". You must regenerate the *entire* JSON manifest.
    -   **Interactive Preview:** No "Play/Pause" logic with audio sync.
    -   **Timeline Model:** The manifest is a flat list of elements, not a track-based timeline.

## 4. Operational Gaps (Dec 2024 Audit)
-   **Color Space:** The biggest technical debt. Video enters as Gamma, blends as Gamma, exits as Linear->Gamma. This 5% brightness error degrades quality.
-   **Timeline Editing:** Sprint 11 (Timeline Model) is defined but not implemented. This is critical for the "Non-Linear Editor" (NLE) capability.
-   **Audio:** Completely missing from the render loop logic so far (mix, stems, sync).

## 5. Architecture for MetaVisKit2
To evolve from a "Renderer" to an "Editor":

### A. The Application Model (New Layer)
We need a stateful logic layer *above* the Render Engine.
-   **`ProjectSession`**: Holds the mutable state (Root Manifest, Undo Stack).
-   **`EditIntent` API**: Structured mutations (`TrimClip`, `AddTrack`, `MoveKeyframe`).
-   **`TimelineModel`**: A proper NLE data structure (Tracks, Clips, Gaps), which *compiles down* to a `RenderManifest`.

### B. The Unified Pipeline
1.  **Ingest:** `VisionProvider` (Analysis).
2.  **Edit:** `TimelineModel` (State).
3.  **Resolve:** `ManifestResolver` (Compilation).
4.  **Render:** `RenderEngine` (Execution).
5.  **Export:** `VideoExporter` (Delivery).

### C. The "Intelligent" Layer
-   **Agent API:** Expose the `EditIntent` API to the LLM agent.
    -   User: "Cut the silence."
    -   Agent: Calls `AnalyzeAudio(silence)`, then `RemoveSegments(ranges)`.
