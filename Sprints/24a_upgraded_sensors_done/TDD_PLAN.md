# TDD Plan: Sprint 24a Upgraded Sensors
**Status:** DONE (2025-12-21). Remaining LiDAR alignment tests are deferred until Asset C exists.

## Test Philosophy
We validate "Devices" by feeding them Real Video Assets (offline) and asserting the properties of the output buffers (Coverage, Stability, Class Presence).

Additionally, we validate that Device Streams can be consumed by the Render Graph ("superpowers"), via integration tests that bind device outputs as textures.

Mandate addition (confidence governance):
- Devices must emit **EvidenceConfidence** using the shared `MetaVisCore` confidence model (conceptually `ConfidenceRecord.v1`).
- Tests must assert reason codes are finite + sorted + stable, and that confidence never increases as evidence degrades.

## Test Assets
*   **Asset A (People):** `Tests/Assets/people_talking/Two_men_talking_202512192152_8bc18.mp4`
    *   *Role:* Validate `FacePartsDevice` (Teeth, Lips).
*   **Asset A2 (People):** `Tests/Assets/people_talking/A_man_and_woman_talking.mp4`
    *   *Role:* Validate `TracksDevice` + general face stability across a mixed-gender dialogue.
*   **Asset A3 (People / Dirty):** `Tests/Assets/people_talking/two_scene_four_speakers.mp4`
    *   *Role:* Validate cut robustness + track loss/reacquisition + "no silent degrade" stability warnings.
*   **Asset B (Subject):** `Tests/Assets/VideoEdit/keith_talk.mov`
    *   *Role:* Validate `MaskDevice` (Foreground Lift).

*   **Asset C (Depth):** (TBD)
    *   *Role:* Validate `DepthDevice` (LiDAR depth sidecar alignment + confidence). This should be a short iOS LiDAR capture with a known near/far subject.

## Model acquisition (new)
Some Sprint 24a tests depend on local model artifacts. Model acquisition is now scripted and normalized into `assets/models/...`:

- MobileSAM CoreML bundles:
    - `./scripts/download_mobilesam_coreml.sh`
- Face parsing CoreML model:
    - `./scripts/download_face_parsing_coreml.sh`

Note: these scripts unblock downloading/placing models; test coverage still requires wiring a `MobileSAMDevice` and/or dense face-parsing inference.

## Test Cases

### 1. `MaskDeviceTests` (Tier 0)
*   **Unit:** `test_foreground_lift_generates_mask`
    *   Active Asset: **Asset B** (Keith).
    *   Action: Feed Frame 0 to `MaskDevice` configured for `.foreground`.
    *   Assert: Output buffer is not empty (mean pixel value > 10).
    *   Assert: Output definition (edges are crisp? optional).
*   **Unit:** `test_mask_stability_metric`
    *   Active Asset: **Asset B**.
    *   Action: Process Frames 0..30.
    *   Assert: `IoU(mask[t], warp(mask[t-1])) >= 0.8`.

*   **Unit:** `test_mask_emits_warning_when_unstable` (contract)
    *   Active Asset: **Asset B** or **Asset A3** (if cut/occlusion reveals instability).
    *   Action: Run a window where stability drops below threshold.
    *   Assert: emits an explicit warning artifact / metadata; never silently degrades.
    *   Assert: downgrades `EvidenceConfidence` with reason `mask_unstable_iou`.

Status: Implemented.
- `MaskDeviceTests` asserts deterministic, governed confidence and warp-based stability IoU on `keith_talk.mov`.
- Cut-window robustness + explicit instability reasons are validated on `two_scene_four_speakers.mp4`.

### 1b. `DepthDeviceTests` (Tier 0)
*   **Unit:** `test_depth_present_or_explicitly_missing`
    *   Active Asset: **Asset C**.
    *   Assert: output depth buffer exists OR emits an explicit “missing depth” state (never silently returns garbage).
    *   Assert: `EvidenceConfidence` is `WEAK`/`INVALID` with reason `depth_missing` when missing.
*   **Unit:** `test_depth_values_in_reasonable_range`
    *   Active Asset: **Asset C**.
    *   Assert: depth min/max exclude obvious invalid ranges (e.g., negative, huge) after masking invalid pixels.
*   **Unit:** `test_depth_alignment_is_stable_under_relink`
    *   Active Asset: **Asset C** proxy + full-res pair.
    *   Assert: depth->RGB registration remains correct after proxy/full-res relink mapping.

Status: Partially implemented.
- Implemented: explicit missing semantics + governed reasons; synthetic depth buffer metrics tests; invalid pixel format throws; present-but-invalid-range is explicitly flagged.
- Remaining: Asset C (real LiDAR) + alignment + relink stability tests.

Note (Sprint 24a update): a minimal depth sidecar v1 format is now defined (`Sprints/24a_upgraded_sensors_done/DEPTH_SIDECAR_V1.md`) with a reference reader. Real alignment/relink remains pending until we have an Asset C capture.


### 2. `FacePartsDeviceTests` (ROI-local whitening; Option B)
*   **Unit:** `test_faceparts_emits_governed_confidence_and_roi_masks`
    *   Active Asset: **Asset B** (Keith).
    *   Action: Run `FacePartsDevice` across a short window.
    *   Assert: governed confidence record shape (finite, sorted reasons).
    *   Assert: mouth/eye ROI masks are OneComponent8 when available.

*   **Unit:** `test_mouth_mask_pixels_are_within_mouthRectTopLeft` (flagship)
    *   Active Asset: **Asset B** (Keith) or **Asset A2**.
    *   Action: When `mouthMask` and `mouthRectTopLeft` are available, assert the mouth mask has no non-zero pixels outside the rect (no bleed).
    *   Assert: when violated, downgrades `EvidenceConfidence` with an explicit governed reason code.

*   **Unit:** `test_whitening_is_strictly_roi_local` (flagship)
    *   Active Asset: **Asset B**.
    *   Action: Run whitening using `mouthRectTopLeft`.
    *   Assert: pixels outside ROI are unchanged.

Optional (env-gated): if a face-parsing model is available, validate that derived masks (e.g., inner-mouth/lips) are produced and remain ROI-local.

Status: Landmarks-first foundation implemented; dense parsing is optional and model-dependent.
- Implemented today:
    - `FacePartsDeviceTests` validates mouth/eye ROI mask generation and emits a normalized `mouthRectTopLeft`.
    - `MouthWhiteningTests` + `FacePartsWhiteningTests` validate strict ROI-local whitening using `mouthRectTopLeft`.
- Remaining:
    - If we adopt dense parsing for stability, freeze one compatible model format + preprocessing contract and add env-gated tests for inner-mouth/lips ROI locality + stability.

### 3. `MobileSAMDeviceTests` (Tier 1)
*   **Unit:** `test_promptable_segmentation`
    *   Active Asset: **Asset B**.
    *   Action: Provide a "Center Point" prompt on the subject.
    *   Assert: Output mask covers the central subject (approximate bbox match).

Status: Implemented (env-gated where models are required).

Implemented today:
- Missing-model semantics are deterministic and governed (no model artifacts required).
- Env-gated smoke test produces a non-empty mask when models are present.
- Env-gated interactive behavior tests:
    - Encoder embedding reuse on repeated prompts (same frame).
    - Prompt affects mask output (non-identical masks).
    - CacheKey-based encoder reuse across frame copies.

Unblocked prerequisites:
- CoreML MobileSAM `.mlpackage` download automation exists (see Model acquisition section above).

## Benchmark Tests (Performance)
*   **Unit:** `test_inference_latency_under_16ms`
    *   Run `MaskDevice` 100 times. Assert avg time < 16ms (60fps).

### Performance gating
Performance tests must be env-var gated (like existing device perf tests) so `swift test` stays fast by default.

## Integration expectations
- Device streams must remain low-level evidence: tests should assert metrics + warnings, not intent.
- Cut robustness: **Asset A3** should not crash devices; resets/rekeys are allowed if deterministic and explicitly surfaced.

## Governance tests (shared)
Add contract tests (fast, deterministic) for the confidence ontology once implemented in `MetaVisCore`:
- Confidence grade mapping determinism (`score -> grade`) via a centralized mapper.
- Reason code vocabulary stability (closed enum; stable raw values; sorted output).
