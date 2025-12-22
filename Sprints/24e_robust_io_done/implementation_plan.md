# Sprint 24e: Robust IO - Implementation Plan

## Goal Description
Unify the Input/Output pipelines and eliminate ad-hoc shell scripts in the CLI. We will replace fragile `ffmpeg` shell-outs with the internal rendering engine, implement a plugin system for Generative Ingest, and clean up IO hygiene (paths, logging, encoding settings).

## User Review Required
> [!IMPORTANT]
> **CLI Behavior Change:** `GeminiAnalyzeCommand` will no longer require `ffmpeg` in PATH for proxy generation, but proxy generation may be slower initially as it uses the internal export pipeline.
> **Potential Breaking Change (if implemented):** Introducing an `EncodingProfile` may require a new `VideoExporter.export(...)` overload and updating call sites.

**Repo reality (2025-12-22):**
**Status (2025-12-22):**
- `GeminiAnalyzeCommand` now generates the inline proxy using `VideoExporter` + `EncodingProfile.proxy(...)` (no `ffmpeg` shell-out on this path).
- `VideoExporter` no longer writes to `/tmp/metavis_debug.log`.
- `MetalSimulationEngine` no longer writes to `/tmp/metavis_engine_debug.log`.
- `LIGMDevice` is plugin-routed via `GenerativeSourcePlugin` with a first `NoiseGeneratorPlugin` implementation.
- `IOContext` exists and is threaded into `GeminiAnalyzeCommand`.

## Proposed Changes

## Implemented

All P0/P1/P2/P3 items above are implemented with the noted sprint scope (scientific FITS robustness remains “time permitting”).

### MetaVisLab
#### [MODIFY] [Sources/MetaVisLab/GeminiAnalyzeCommand.swift](../../Sources/MetaVisLab/GeminiAnalyzeCommand.swift)
- Remove `Process()` calls to `ffmpeg`.
- Instantiate `MetaVisExport.VideoExporter`.
- Provide a `QualityProfile` optimized for proxy (360p).
- Use `IOContext` for temp file placement.

#### [MODIFY] [Sources/MetaVisLab/MetaVisLabMain.swift](../../Sources/MetaVisLab/MetaVisLabMain.swift)
- Introduce `IOContext` struct (documents, cache, temp paths).
- Pass `IOContext` to all commands via `LabCommand` protocol refactor.

**Scope note:** `MetaVisLab` contains other `ffmpeg` usages (e.g. transcript audio trimming and some extract helpers). This sprint’s P0 is to remove `ffmpeg` from the Gemini proxy path; broader ffmpeg removal should be treated as separate, explicitly-scoped work.

### MetaVisIngest
#### [MODIFY] [Sources/MetaVisIngest/LIGMDevice.swift](../../Sources/MetaVisIngest/LIGMDevice.swift)
- **Remove** mock `Task.sleep` logic.
- **Micro-Architecture:**
    - Define `GenerativeSourcePlugin` protocol.
    - Implement `NoiseGeneratorPlugin` (Static/Perlin) as a reference.
    - Router logic to dispatch `perform(action: "generate")` to plugins.
- **Test:** Update `Tests/MetaVisIngestTests/LIGMDeviceTests.swift` to validate plugin routing instead of today’s stub URL behavior.

#### [MODIFY] [Sources/MetaVisIngest/FITS/FITSReader.swift](../../Sources/MetaVisIngest/FITS/FITSReader.swift)
- (Time Permitting) Replace full-payload reads with `mmap` or strip/scanline reads for very large files.
- Improve `FITSError` cases with more context (e.g., `unexpectedEOF(offset:expected:got:)`) and ensure errors include file offsets/header context.

### MetaVisExport
#### [MODIFY] [Sources/MetaVisExport/VideoExporter.swift](../../Sources/MetaVisExport/VideoExporter.swift)
- **Remove** hardcoded file logging to `/tmp`.
- Inject `TraceSink` logging.
- **Refactor** `exportMovie` to take `EncodingProfile` (bitrate, keyframeInterval, audioBitrate).
- Ensure `pixelBufferAdaptor` logic reuses pools where possible.

## Verification Plan

### Automated Tests
1.  **Plugin System:**
    - Test `LIGMDevice` with a `MockPlugin`. Verify `perform` calls the plugin.
2.  **Encoding Config:**
    - Test `VideoExporter` with two different profiles (Low/High). Verify output file sizes differ significantly.
3.  **Path Hygiene:**
    - Unit test `IOContext`. Ensure paths are absolute and accessible.

### Manual Verification
1.  **Unified Export:**
    - Run `lab gemini-analyze input.mov`.
    - Monitor CPU/GPU usage (should see Metal usage, not `ffmpeg` process).
    - Verify output proxy quality.
2.  **Logging Cleanliness:**
    - Verify logging is routed through `TraceSink`/`OSLog` and no hardcoded debug-log paths remain.
