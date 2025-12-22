# MetaVisExport Code Review

**Date:** 2025-12-21
**Reviewer:** Antigravity Agent
**Module:** `MetaVisExport`

## 1. Executive Summary

`MetaVisExport` handles the final stage of the pipeline: encoding `Timeline` rendering results into video files (`.mov`, `.mp4`) and generating associated sidecars (captions, thumbnails). It leverages `AVAssetWriter` and `VideoToolbox`.

**Strengths:**
- **Parallel Pipeline:** Uses Swift Concurrency (`TaskGroup`) to encode audio and video in parallel lanes, preventing audio rendering from blocking video frame dispatch.
- **Backpressure Handling:** Implements explicit waiting logic (`awaitReadyForMoreMediaData`) to prevent memory explosions when the writer cannot keep up with the renderer.
- **Sidecar Infrastructure:** Robust, zero-dependency implementations for VTT, SRT, and Contact Sheet generation.
- **Manifests:** `DeliverableManifest` provides a comprehensive JSON record of *what* was exported, including QC metrics and sidecar validation.

**Critical Gaps:**
- **Debug Logging:** Heavy use of `/tmp/metavis_debug.log` via `FileHandle` in production code. This is a security/performance risk and should be replaced with `OSLog` or the `TraceSink` abstraction.
- **Hardcoded Settings:** `VideoExporter` has hardcoded bitrates (~0.08 bpp for HEVC) and audio settings (AAC 128kbps).
- **Pixel Buffer Copies:** The module has checks for pixel formats (BGRA vs RGBAHalf) but relies on `AVAssetWriterInputPixelBufferAdaptor` creating new pools, which might incur copies.

---

## 2. Detailed Findings

### 2.1 Video Pipeline (`VideoExporter.swift`)
- **Concurrency:** The `runParallelExport` method uses a `TaskGroup` to spawn `audio` and `video` tasks. This is excellent for throughput.
- **Safety:** Explicit checks for `pixelBufferPool` exhaustion and `writer.status` prevent silent failures.
- **Refinement:** The manual "debug log" writing to `/tmp` on line 39+ is thread-unsafe (though `append` uses seek-to-end, collisions can corrupt it) and improper for a library.

### 2.2 Audio Handling
- **Flow:** Renders audio in chunks using `AudioTimelineRenderer`, waits for writer readiness, then appends.
- **Issue:** The logic for converting `AVAudioPCMBuffer` to `CMSampleBuffer` (`createReferenceSampleBuffer`) involves manual memory binding. While functionally correct for planar-to-interleaved conversion, it is complex and brittle.

### 2.3 Sidecars (`SidecarWriters.swift`)
- **VTT/SRT:** Pure Swift implementation of caption parsers and renderers. 
- **Thumbnails:** Uses `AVAssetImageGenerator`. `writeContactSheetJPEG` cleanly handles grid layout using CoreGraphics.
- **Recommendation:** `TranscriptSidecarWriter` uses a deterministic integer-partitioning algorithm to align words to ticks. This is excessively precise but guarantees stability across runs.

### 2.4 Governance (`ExportGovernance`)
- **Validation:** `ExportPreflight` checks against `FeatureRegistry` to ensure all effects used in the timeline are known and valid for export.
- **Policy:** Enforces `ProjectLicense` (watermarking, max resolution) before starting the export.

---

## 3. Recommendations

1.  **Remove ad-hoc logging:** Replace the `/tmp/metavis_debug.log` writing with a structured logging system.
2.  **Configurable Encoding:** Expose bitrate, profile, and audio settings in a `EncodingProfile` struct rather than hardcoding them in `VideoExporter`.
3.  **Unit Tests for Sidecars:** The VTT/SRT parsers are complex string manipulation logic; they should be verified with comprehensive unit tests (if not already present).
