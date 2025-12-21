# MetaVisExport Assessment

## Initial Assessment
MetaVisExport provides a robust, professional-grade export pipeline. It goes beyond simple "Save As" by treating exports as "Deliverables" that include sidecars (captions, thumbnails) and automated Quality Control (QC) reports, reflecting the system's prosumer/Hollywood focus.

## Capabilities

### 1. Parallel Export (`VideoExporter`)
- **Architecture**: Uses `TaskGroup` to encode Video and Audio in parallel, preventing audio processing from blocking video rendering (or vice-versa).
- **Safety**: Implements explicit backpressure (`awaitReadyForMoreMediaData`) to keep memory usage low during long exports.
- **Audio**: Custom handling to convert `AVAudioPCMBuffer` to interleaved `CMSampleBuffer` for AAC encoding.

### 2. Deliverable Manifests
- **Concept**: An export is not just a `.mov` file; it's a bundle containing the video, sidecars, and a JSON manifest.
- **Sidecars**:
    - **Captions**: VTT and SRT (converted from timeline assets).
    - **Images**: Thumbnails and Contact Sheets generated from the rendered video.
- **QC Integration**: Automatically runs inspection (Metadata, Content, Sidecar checks) post-export and embeds the report in the manifest.

### 3. Governance
- **Preflighting**: Checks user plan limits (resolution) and watermark requirements before starting the expensive render.
- **Tracing**: Extensive open-telemetry style tracing (`trace.record`) for performance monitoring.

## Technical Gaps & Debt

### 1. Manual Audio Interleaving
- **Issue**: `VideoExporter` manually interleaves audio channels using unsafe pointer manipulation to satisfy `CMBlockBuffer` requirements.
- **Risk**: Hard to maintain and error-prone.
- **Fix**: Move to a dedicated, unit-tested `AudioBufferUtils` in `MetaVisAudio` or `MetaVisCore`.

### 2. Hardcoded Debug Logging
- **Issue**: Writes debug logs to `/tmp/metavis_debug.log`.
- **Debt**: Not thread-safe for parallel tests, not suitable for production.
- **Fix**: Use `OSLog` or the injected `TraceSink`.

### 3. `AVAssetWriter` Fragility
- **Issue**: Heavily reliant on `AVAssetWriter`. Errors are often cryptic (`code: -11800`), and error handling is basically "catch and fail".
- **Improvement**: Better error mapping/recovery or sanity checks (e.g., checking disk space, ensuring valid sample buffers).

## Improvements

1.  **Refactor Audio Utils**: Extract the PCM-to-CMSampleBuffer logic.
2.  **Streaming Sidecars**: Generate thumbnails/contact sheets *during* the render pass instead of reading the file back after export (saves disk I/O).
3.  **ProRes Options**: Expose more ProRes flavors (422, LT, HQ) in `QualityProfile`.
