# Sprint 24d: Engine Hardening - Specification

**Goal:** Transform the prototype rendering engine into a production-grade, secure, and dependency-free foundation.

## Objectives

1.  **Eliminate External Dependencies (Priority P0)**
    *   **Repo Reality (today):** `ClipReader` is **native-first** for EXR decode (CoreImage/ImageIO) with a **fallback to `ffmpeg`** when EXR decode is unavailable on the host; **FITS decoding is pure Swift** via `FITSReader`.
        *   EXR: `Sources/MetaVisSimulation/ClipReader.swift` (`FFmpegEXRDecoder`)
        *   FITS: `Sources/MetaVisIngest/FITS/FITSReader.swift` + `Sources/MetaVisSimulation/ClipReader.swift` (`FITSStillDecoder`)
    *   **Problem:** Some environments cannot decode EXR via CoreImage/ImageIO; the engine falls back to `ffmpeg` for EXR in those cases.
    *   **Requirement (full):** Replace the `ffmpeg` fallback with a dependency-free EXR decoder (e.g. TinyEXR wrapper) and remove any dependence on `ffmpeg` being present.
    *   **Success Metric (full):** Rendering an EXR-backed timeline works when `ffmpeg` is not installed / not on PATH.
    *   **Non-goal (for this sprint unless explicitly added):** `MetaVisLab` contains commands that invoke `ffmpeg` for auxiliary tasks (e.g. extracting frames). Those are outside the engine EXR decode path.

2.  **Portable Shader Loading (Priority P0)**
    *   **Repo Reality (today):** `MetalSimulationEngine` has a hardcoded absolute-path fallback that reads `.metal` sources directly from disk:
        *   `Sources/MetaVisSimulation/MetalSimulationEngine.swift` (`compileLibraryFromHardcodedSources` reads from `/Users/kwilliams/Projects/metavis_render_two/metaviskit2/Sources/MetaVisGraphics/Resources/*.metal`)
    *   **Problem:** This prevents portability and makes shader loading dependent on one developer machine path.
    *   **Requirement:** Remove the absolute-path fallback.
        *   Preferred: always load the packaged default library via `device.makeDefaultLibrary(bundle: GraphicsBundleHelper.bundle)`.
        *   Optional dev-mode fallback: compile from `.metal` *resources* via `Bundle.module` URLs (not absolute paths).
    *   **Success Metric:** Engine initializes successfully on a clean checkout on another machine (no user-specific paths), and fails with a clear error if shader resources are missing.

3.  **Deterministic Rendering (Priority P2)**
    *   **Repo Reality (today):**
        *   `MetalSimulationEngine.logDebug` prefixes logs with `Date()` and writes to `/tmp/metavis_engine_debug.log`.
        *   `FFmpegEXRDecoder` uses `Date()` for timeout bookkeeping.
    *   **Problem:** Determinism is threatened by wall-clock usage and uncontrolled side effects in core paths (especially if logs are treated as artifacts).
    *   **Requirement:** Ensure render outputs (and any “contract artifacts”) are deterministic and that render behavior does not depend on wall-clock time.
        *   If logs are considered out-of-band, explicitly document them as non-artifacts and/or gate them behind a deterministic logger.
    *   **Success Metric:** Same `RenderRequest` yields byte-identical outputs across runs (given same inputs and environment).

4.  **Architecture Isolation (Priority P1)**
    *   **Problem:** `FeedbackLoopOrchestrator` in `MetaVisCore` accesses the filesystem directly, making it untestable and tightly coupled to the OS.
    *   **Requirement:** Refactor to use a `FileSystemAdapter` protocol.
    *   **Success Metric:** Unit tests for Orchestrator run in-memory without creating temp files.

5.  **Memory Stability (Priority P1)**
    *   **Repo Reality (today):**
        *   Frame cache is bounded by `maxCachedFrames` (default 24).
        *   Still caches are **unbounded** (`stillPixelBuffers` grows per unique EXR/FITS URL + resolution).
        *   Decoder state cache is **unbounded** (`decoders` grows per unique video URL + resolution).
        *   No memory-pressure hooks exist.
    *   **Problem:** Long sessions / many assets can grow caches without release under memory pressure.
    *   **Requirement:** Add a cache policy + memory-pressure hooks to clear/trim caches deterministically.
    *   **Success Metric:** Under a simulated memory-pressure signal, ClipReader clears large caches (at minimum: `stillPixelBuffers`, `decoders`, and the frame cache).

6.  **Data Integrity (Priority P2)**
    *   **Repo Reality (today):** `MetaVisTimeline` has `Clip.overlaps(with:)` but no `Timeline.validate()` / `Track` invariants, and nothing prevents overlaps.
        *   `Sources/MetaVisTimeline/Timeline.swift`
    *   **Problem:** Overlapping clips on the same track creates ambiguous render intent.
    *   **Requirement:** Add a validation API (and optionally enforce invariants in mutators) that detects overlaps within a track.
    *   **Success Metric:** A `Timeline.validate()` (or equivalent) reports overlap errors for overlapping clips.

7.  **Production Readiness (Priority P2)**
    *   **Repo Reality (today):** `MetalSimulationEngine.configure()` falls back to runtime compilation from disk sources if default library loading fails or is missing required kernels.
    *   **Problem:** The engine relies on runtime compilation fallbacks and debug-centric behavior.
    *   **Requirement:** Add a "Production Mode" flag that:
        1.  Crashes/Fails logic if `default.metallib` is missing (no silent fallback).
        2.  Optionally uses Metal Function Constants for debug features to optimize release shaders.
    *   **Success Metric:** Release build compiles optimized shaders and fails fast on missing resources.

## Scope Changes
*   **Moved to Sprint 4:** "Secure Configuration" (Gemini API Keys and EntitlementManager) are Application-level concerns, not Engine-level.

## Hardening notes (general)

### Determinism & acceptance test hygiene
- **Requirement:** Strict “golden”/acceptance checks must be explicitly gated (e.g. `ENV_VAR=1`) so normal developer runs and CI can remain stable.
- **Requirement:** Acceptance tests should be fixture-driven (pre-generated outputs) and support an override directory env var to enable iteration without modifying test code.

### Time alignment safety
- **Requirement:** Any pipeline that aligns word-times, frames, or samples using `Double` must avoid exact-boundary comparisons that can fail due to floating-point representation.
- **Success Metric:** Boundary word/sample alignments are stable across machines/toolchains (use an epsilon for comparisons).

