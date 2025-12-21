# Sprint 24a Gap Analysis (DONE — follow-ups deferred)
**Date:** 2025-12-21
**Status:** DONE (Sprint intent satisfied: Tier‑0 devices + governed confidence + LiDAR-ready scaffolding)

This document is a reality-based gap/tech-debt audit of Sprint 24a (“Upgraded Sensors”), grounded in:
- `Sprints/24a_upgraded_sensors_done/PLAN.md`
- `Sprints/24a_upgraded_sensors_done/TDD_PLAN.md`
- `Sprints/24a_upgraded_sensors_done/DATA_DICTIONARY.md`
- Current code under `Sources/MetaVisPerception/*` and related tests.

## What’s already done (confirmed in code/tests)
- Tier-0 devices implemented and exercised by deterministic tests:
  - `MaskDevice` (Vision segmentation) with warp-based stability IoU + keyframe sampling strategy.
  - `TracksDevice` (Vision tracking) with governed reacquire semantics.
  - `FlowDevice` (Vision optical flow) with 16F output.
  - `DepthDevice` missing/invalid semantics (synthetic coverage); no real Asset C alignment yet.
- Device-level governance is in place:
  - `ConfidenceRecordV1` with finite, sorted reason codes.
  - No silent degrade: explicit warning segments are emitted during ingest.
- Face whitening foundation shipped:
  - `FacePartsDevice` landmarks-first ROI masks + `mouthRectTopLeft`.
  - ROI-local whitening tests (`MouthWhiteningTests`, `FacePartsWhiteningTests`).
- Standardization + orchestration (beyond original PLAN):
  - `PerceptionDevice` protocol (`infer(_:)`) + adapters.
  - `PerceptionDeviceHarnessV1` (perf loops) and env-gated perf tests.
  - `PerceptionDeviceGroupV1` warm/cool orchestration; now wired into `MasterSensorIngestor`.
- Tier-1 groundwork (beyond original PLAN):
  - `MobileSAMDevice` exists with safe-by-default missing-model semantics + env-gated tests.
- LiDAR readiness scaffolding:
  - Sidecar discovery helper + presence test (env-gated by `METAVIS_LIDAR_ASSET_C_MOVIE`).
  - Depth sidecar v1 (`*.depth.v1.bin` + `*.depth.v1.json`) is now defined with a reference reader + deterministic tests.

## Deferred follow-ups (not blocking Sprint 24a acceptance)
### 1) Depth “Asset C” and real alignment contract (highest risk)
**Gap:** We do not yet have a real LiDAR sidecar test asset + alignment/relink validation.

Update: the LiDAR readiness tests now decode at least one v1 depth frame when `METAVIS_LIDAR_ASSET_C_MOVIE` is set and `AssetC.depth.v1.json` exists, and a lightweight env-gated harness exists to validate value sanity (still defers true alignment/relink).

Note (explicit deferral): We will come back to LiDAR/Asset C after an iOS LiDAR capture is available. Until then, we keep moving on the non-LiDAR critical path.

Deliverables:
- Acquire a short iOS LiDAR capture (Asset C) + sidecar(s) accessible to tests.
- Implement and test:
  - Depth/RGB alignment correctness.
  - Proxy/full-res relink stability.

### 2) Face micro-segmentation / “teeth” flagship capability
**Decision (chosen): Option B (ROI-local whitening).**

We treat whitening as ROI-local + landmarks-driven (optionally guided by inner-mouth/lips parsing) and do not hard-require a dedicated teeth class.

Deliverables (either option):
- Explicit contract tests:
  - Strict ROI locality.
  - Temporal stability metric (or explicit warnings when unstable).
  - Governed confidence reason codes when invariants are violated.

Update (in code):
- ROI locality is enforced with deterministic tests, and the device now clamps any mouth-mask pixels outside `mouthRectTopLeft` and emits a governed reason code (`mouth_mask_outside_mouth_roi`) if this ever occurs (regression guard).

### 3) MobileSAM “interactive” architecture and correctness tests
**Update:** MobileSAM now supports embedding reuse for interactive prompting:
- Same-frame reuse (same `CVPixelBuffer` object).
- Cache-key reuse (caller-supplied `cacheKey`, e.g. asset/time/keyframe), including across frame copies.

**Update (real runtime path):** There is now a concrete, end-to-end entry point that exercises cacheKey reuse outside tests:
- `MobileSAMSegmentationService` provides a canonical cacheKey builder (`mobilesam|v1|src=...|t=...|WxH`) and a thin wrapper over `MobileSAMDevice`.
- `MetaVisLab mobilesam segment ...` runs 1–2 prompts on the same frame while reusing the same cacheKey, writes PNG masks, and prints `encoderReused`.

**Update (sourceKey definition):** A stable `sourceKey` implementation now exists and is reused across ingest + MobileSAM:
- `SourceContentHashV1` computes a content hash for local file URLs (stable across renames/machines).
- `MobileSAMSegmentationService.CacheKey.make(url:...)` uses `SourceContentHashV1` by default.
- `MetaVisLab mobilesam segment ...` now uses the content-hash-based cacheKey scheme by default.

**Remaining gap:** The ideal UX still benefits from a more explicit two-step API and a cache key derived from (asset/time/keyframe) rather than object identity.

Deliverables:
- DONE: embedding reuse on repeated prompts for the same frame object + env-gated cache-hit test.
- DONE: embedding cache keyed by caller-provided `cacheKey` + env-gated test proving reuse across frame copies.
- DONE: env-gated prompt-difference correctness test (“prompt affects mask”).
- DONE: canonical cacheKey builder exists in `MobileSAMSegmentationService` (asset/time/size based).
- TODO: if/when a render-graph or Director UI consumes MobileSAM, thread the canonical `cacheKey` scheme through those call sites.
- (Optional) integrate into a render-node or service API if Sprint 24a requires render-graph consumption.

### 4) Render-graph/device-stream integration beyond person mask
**Gap:** Mask-driven grading is covered, but Flow/Depth/FaceParts “superpowers” are not fully integrated as device-driven render inputs.

Deliverables (if in-scope for 24a):
- Add render-graph bindings or nodes for:
  - Flow-warped masks.
  - Depth-driven occlusion/DOF.
  - FaceParts-driven beauty/whitening using dense parsing (if chosen).

## Tech debt (cleanups that reduce future risk)
### A) Spec drift: `render(time:)` vs `infer(_:)`
The PLAN’s proposed `DeviceProtocol render(time:) -> T` diverged from the implemented `PerceptionDevice.infer(_:)` standardization.

Recommendation:
- Either update Sprint 24a docs to reflect `infer(_:)` as the canonical entrypoint, or add a thin adapter that preserves the original conceptual `render(time:)` API for render-graph usage.

### B) MobileSAM performance / caching
- Current: same-frame + cacheKey encoder embedding caches exist; repeated prompts can skip the encoder.
- Remaining: explicit two-step encoder/prompt API (optional) + consistent cacheKey adoption at call sites.

Recommendation:
- Keep embedding caching and consider a two-step API.

### C) Face parsing model compatibility
- Face parsing is inherently “model zoo messy”: label maps, preprocessing, and output shapes vary.

Recommendation:
- Freeze a single supported model format + explicit preprocessing contract; reject incompatible models with governed reasons.

### D) LiDAR sidecar contract not standardized
Resolved (foundation): v1 `*.depth.v1.bin` + `*.depth.v1.json` is now defined and has a reference reader.

Remaining: real Asset C capture + alignment/relink tests.

## Suggested next steps (prioritized)
1. Depth: acquire Asset C + implement alignment/relink tests (format v1 + reader already exist).
2. FaceParts: if dense parsing is adopted later, freeze one model format + preprocessing contract.
3. MobileSAM: thread canonical cacheKey through any future production call sites (greenfield).

