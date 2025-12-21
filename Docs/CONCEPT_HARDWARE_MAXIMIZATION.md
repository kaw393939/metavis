# Concept: Hardware Maximization & Universal IO

> **Goal**: "Slip into your workflow."
> We must respect the hardware the user paid for by using *all* of it, and respect their pipeline by reading/writing *their* formats.

## 1. Maximizing the Silicon (Apple & Beyond)
The user paid for an M-Series chip. We must use every distinct compute unit, not just the CPU/GPU.

### The "Compute Triad" Strategy
We assign tasks to specific silicon blocks:

1.  **Media Engine (VideoToolbox)**: 
    *   *Task*: Decoding/Encoding ProRes and HEVC. 
    *   *Why*: It's dedicated hardware. Zero CPU usage.
    *   *Manifestation*: `MetaVisIngest` and `MetaVisExport` use `VTDecompressionSession` and `VTCompressionSession` exclusively for supported formats.
2.  **Neural Engine (ANE)**:
    *   *Task*: AI Inference (AutoColor, AutoLogger).
    *   *Why*: massive throughput for CoreML, keeping GPU free for rendering.
    *   *Manifestation*: `MetaVisPerception` explicitly requests `.all` compute units but prioritizes ANE for "Background Agents".
3.  **GPU (Metal)**:
    *   *Task*: Pixel Rendering, Compositing, Color Science.
    *   *Why*: Massive parallel fp16 throughput.
    *   *Manifestation*: `MetaVisSimulation` is 100% Metal Compute Shaders.

### Unified Memory Architecture (UMA)
*   **Zero-Copy Promise**: We pledge never to copy a pixel buffer from CPU to GPU if we can help it. `IOSurface` is the currency of the realm.

## 2. Universal IO (The "Universal Adaptor")
We are a "Workflow Node". We must accept anything and output anything.

### A. The "Smart Ingest" Layer
We don't just "open files". We analyze and adapt.
*   **Container Agnostic**: `.mov`, `.mp4`, `.mxf`, `.exr`.
*   **Codec Agnostic**:
    *   *Native*: ProRes, H.264, HEVC (via Media Engine).
    *   *Professional*: DNxHR, CineForm (via software bridging or custom Metal decoders).
    *   *Image Sequences*: DPX, EXR, PNG, TIFF (via `ImageIO` / `TextureLoader`).

### B. The "Modular Exporter"
Exporting is just "Encoding a Signal". The `ExportModule` connects a `SignalSource` (Timeline) to a `CodecWriter`.
*   **Plug-in Architecture**: 
    *   `ProResWriter` (Native)
    *   `YoutubePreflightWriter` (H.264, optimized bitrate, loudness norm)
    *   `ArchivalWriter` (EXR Zip16)
*   **Extensibility**: Adding a new format (e.g., "WebM") is just implementing the `CodecWriter` protocol.

## 3. Workflow Integration
> "Just slip into your workflow."

*   **Round-Tripping**: We support XML/EDL/OTIO import/export.
    *   A user can start in Premiere, send XML to MetaVis for "AutoColor", and get an XML back.
    *   We act as a **"Processing Step"** in a larger pipeline, not just a walled garden.

## 4. Summary
*   **Respect the Hardware**: If the fan spins up, we failed. We use the specialized circuits.
*   **Respect the Pipeline**: We are a polite guest in the user's workflow. We speak their language (Formats) and fit their schedule (Speed).
