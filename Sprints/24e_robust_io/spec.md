# Sprint 24e: Robust IO - Specification

**Goal:** Unify the Input/Output pipelines and eliminate ad-hoc shell scripts in the CLI.

## Objectives

1.  **Unified Export Strategy (Priority P0)**
    *   **Problem:** `GeminiAnalyzeCommand.swift` uses `Process()` to shell out to `ffmpeg` for proxy generation, bypassing the engine.
    *   **Requirement:** Refactor `GeminiAnalyzeCommand` to use `MetaVisExport.VideoExporter.export()` with a constrained `QualityProfile` and `Time` range.
    *   **Success Metric:** `GeminiAnalyzeCommand` runs without `ffmpeg` installed and uses `VideoExporter` trace logs.

    **Status (2025-12-22):**
    *   `GeminiAnalyzeCommand` now generates `gemini_proxy_360p_60s.mp4` using `MetaVisExport.VideoExporter` + `EncodingProfile.proxy(...)` (no `Process()` / no `ffmpeg` dependency for this path).
    *   Other `MetaVisLab` commands still use `ffmpeg` (out of scope for this sprint’s P0).

2.  **Generative Ingest Plugins (Priority P1)**
    *   **Problem:** `LIGMDevice.swift` is a hardcoded stub returning fake "ligm://" URLs. It has no extensibility.
    *   **Requirement:** Define `GenerativeSourcePlugin` protocol. Create `NoiseGeneratorPlugin` as the first implementation (generating static/perlin noise textures). Refactor `LIGMDevice` to load plugins.
    *   **Success Metric:** `LIGMDevice.perform(action: "generate", ...)` acts as a router to the correct plugin based on the prompt or params.

    **Status (2025-12-22):**
    *   Added `GenerativeSourcePlugin` and a first plugin (`NoiseGeneratorPlugin`).
    *   `LIGMDevice` routes matching prompts to plugins and preserves legacy fallback behavior for non-matching prompts.

3.  **Path Hygiene (Priority P2)**
    *   **Problem:** `GeminiAnalyzeCommand` and `MetaVisLab` commands often default to `/tmp` or local paths without validation.
    *   **Requirement:** Introduce `IOContext` struct passed to commands, defining compliant `processTemp` and `documents` directories.
    *   **Success Metric:** No hardcoded user-specific absolute paths; paths are passed as URLs or derived from an explicit IO context.

    **Status (2025-12-22):**
    *   Added `IOContext` in `MetaVisCore` and threaded it into `GeminiAnalyzeCommand`.

4.  **Production Logging (Priority P2)**
    *   **Problem:** `VideoExporter` and `MetalSimulationEngine` write debug logs to `/tmp/metavis_debug.log` using file handles. This is thread-unsafe and insecure.
    *   **Requirement:** Replace custom file I/O with `MetaVisCore.TraceSink` (structured logging) or `OSLog`.
    *   **Success Metric:** No hardcoded debug-log file paths; logging is injected/structured.

    **Status (2025-12-22):**
    *   `VideoExporter` no longer writes to `/tmp/metavis_debug.log`; debug breadcrumbs are routed via `TraceSink` / `OSLog`.
    *   `MetalSimulationEngine` no longer writes to `/tmp/metavis_engine_debug.log`; when enabled, engine debug logs go to `OSLog`.

5.  **Configurable Encoding (Priority P3)**
    *   **Problem:** `VideoExporter` has hardcoded bitrates (~0.08 bpp) and AAC settings.
    *   **Requirement:** Refactor `exportMovie` to accept an `EncodingProfile` parameter, decoupling settings from the execution logic.
    *   **Success Metric:** Can export a ProRes 422 HQ master and a low-bitrate H.264 proxy using the same pipeline.

    **Status (2025-12-22):**
    *   Added `EncodingProfile` and plumbed it through `VideoExporter` so callers can override bitrate/GOP/audio settings.

6.  **Scientific Data Robustness (Priority P3)**
    *   **Problem:** `FITSReader` reads entire files into `Data`, risking OOM on large datasets, and throws generic errors.
    *   **Requirement:** (Time Permitting) Implement memory-mapped reading or strip-based reading. Improve error types to include file offsets/headers.
    *   **Success Metric:** Reading a >2GB FITS fake file does not spike RAM usage.

    **Repo reality (2025-12-22):**
    *   `Sources/MetaVisIngest/FITS/FITSReader.swift` already uses `FileHandle`-based reads and defines a `FITSError` enum.
    *   `read(url:)` still materializes the image payload into memory for full-frame ingest; there is also an internal `readFloat32Scanline(...)` helper for incremental reads.

## Scope Changes
*   **Clarification:** "Input Strategy" for FITS/EXR is handled in Sprint 24d (core hardening + decoders). Sprint 24e focuses on robust IO behaviors and *generative* ingest (plugins).

## Dependencies
*   Depends on Sprint 24d (hardening) to ensure the render engine is stable enough for `GeminiAnalyzeCommand` to rely on it.
