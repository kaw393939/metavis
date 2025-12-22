# Sprint 24d: Engine Hardening - Implementation Plan

## Goal Description
Transform the prototype rendering engine into a production-grade, secure foundation. We will harden EXR ingest (native-first decode with a fallback where host codecs are unavailable), ensure portability (remove hardcoded paths), improve testability (abstract IO), and harden the runtime against memory potential and data integrity issues.

## User Review Required
> [!IMPORTANT]
> **EXR Decode Behavior (Engine Path):** The engine now attempts a native EXR decode first (CoreImage/ImageIO). If EXR decode is unavailable on the host, it falls back to `ffmpeg` for EXR stills. FITS decoding remains native/pure Swift.
> Note: some `MetaVisLab` utilities also invoke `ffmpeg` for non-engine tasks (e.g. frame extraction); those are separate from `ClipReader`.
> **Breaking Change:** `FeedbackLoopOrchestrator` init signature will change to accept a `FileSystemAdapter`.

## Proposed Changes

### MetaVisCore
#### [MODIFY] [Sources/MetaVisCore/FeedbackLoopOrchestrator.swift](../../Sources/MetaVisCore/FeedbackLoopOrchestrator.swift)
- Introduce `FileSystemAdapter` protocol.
- Refactor `run` method to use the adapter instead of `FileManager.default`.
- Add `InMemoryFileSystem` for testing.

#### [MODIFY] [Sources/MetaVisCore/Time.swift](../../Sources/MetaVisCore/Time.swift)
- Verify `Tick` precision (Audit only, as per review strength).

### MetaVisSimulation
#### [MODIFY] [Sources/MetaVisSimulation/ClipReader.swift](../../Sources/MetaVisSimulation/ClipReader.swift)
- **Prefer** native EXR decode when available (CoreImage/ImageIO).
- **Fallback** to `ffmpeg` for EXR stills when native decode is unavailable on the host.
- **Keep** FITS decoding as-is (already native/pure Swift via `FITSReader`).
- (Optional follow-on) Implement a fully dependency-free EXR decoder (e.g., TinyEXR wrapper) if "works without `ffmpeg`" is a hard requirement.
- Add memory-pressure handling + explicit cache management.
    - Note: the frame cache is already bounded by `maxCachedFrames`; the unbounded parts today are `stillPixelBuffers` and `decoders`.
    - Add `clearCaches()` / `trimCaches(policy:)` so tests can assert behavior.

#### [MODIFY] [Sources/MetaVisSimulation/MetalSimulationEngine.swift](../../Sources/MetaVisSimulation/MetalSimulationEngine.swift)
- Remove hardcoded absolute path `/Users/kwilliams/...`.
- Implement consistent SwiftPM resource lookup (via `GraphicsBundleHelper.bundle` / `Bundle.module`).
- Add `ProductionMode` configuration enum.
- In `ProductionMode`, disable "Hardcoded Source" fallback.
- Replace `Date()` logging with `RenderRequest.time` or monotonic clock for determinism.

### MetaVisGraphics
#### [MODIFY] [Sources/MetaVisGraphics/GraphicsBundleHelper.swift](../../Sources/MetaVisGraphics/GraphicsBundleHelper.swift)
- Ensure robust `default.metallib` lookup supporting both SPM and Bundle environments.

#### [MODIFY] [Sources/MetaVisGraphics/Resources/*.metal](../../Sources/MetaVisGraphics/Resources)
- (Optional) Introduce function constants for debug-only shader branches.

### MetaVisTimeline
#### [MODIFY] [Sources/MetaVisTimeline/Timeline.swift](../../Sources/MetaVisTimeline/Timeline.swift)
- Add `validate()` method.
- Check for overlapping clips within the same `Track`.
- Return detailed `ValidationError` collection.

## Verification Plan

### Fixture-driven acceptance tests (pattern)
- Prefer pre-generated fixtures for strict acceptance checks.
- Add an env-var override for the fixture directory so devs can regenerate outputs and re-run without touching test code.
- Gate strict assertions behind an explicit env var (keeps CI/dev runs stable).

### Automated Tests
1.  **Architecture Isolation:**
    - Run `FeedbackLoopOrchestratorTests` with `InMemoryFileSystem`. Assert no files created on disk.
2.  **Memory Stability:**
    - Unit test: Populate ClipReader caches. Trigger a test seam (preferred) or simulated memory pressure. Assert caches are cleared/trimmed.
3.  **Data Integrity:**
    - Unit test: Create `Timeline` with overlapping clips. Call `validate()`. Assert error returned.
4.  **Portability:**
    - Ensure the engine never reads shader sources via an absolute path. Run engine initialization on a clean checkout. Assert it loads via bundle (or fails fast with a clear error in production mode).

### Manual Verification
1.  **EXR Decode Fallback:**
    - On a machine that cannot natively decode EXR via CoreImage/ImageIO, ensure `ffmpeg` is installed.
    - Render a timeline with EXR inputs.
    - Verify HDR values are preserved and non-finite values sanitize.

2.  **Dependency-free EXR (Optional / follow-on):**
    - If we add TinyEXR (or similar), uninstall/rename `ffmpeg`.
    - Render a timeline with EXR inputs.
    - Verify success.
