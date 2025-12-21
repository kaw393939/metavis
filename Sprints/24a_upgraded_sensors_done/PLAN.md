# Sprint 24a: Upgraded Sensors (The Ideal Package)
**Status:** DONE (2025-12-21)

## Goal
Implement the **2025 Ideal Sensor Package** to provide the renderer with dense, stable, mask-rich streams for "Hollywood-grade" compositing and color grading.

This sprint also establishes the foundation for the two-product pipeline:
- **iOS Sensor App**: records 1080p proxy + LiDAR/depth sidecars (and optional IMU), then relinks to full-res media later.
- **macOS Director/Compiler**: consumes proxy + sidecars for fast preview, then recompiles against full-res on relink.

## Design Principle
**Everything is a Device Stream.**
- `MaskDevice` (Segmentation)
- `FacePartsDevice` (Landmarks ROI + optional inner-mouth/lips parsing)
- `FlowDevice` (Motion)
- `DepthDevice` (LiDAR / depth texture)

## Code Integration Strategy (DRY)
We will leverage existing infrastructure to avoid wheel reinvention:
- **Time:** Use `MetaVisCore.Time` (Rational) for all timestamps.
- **Buffers:** Use `CoreVideo.CVPixelBuffer` directly (standard currency in `ClipReader`).
- **Ingest:** Model `MaskDevice` after `ClipReader` (Actor-based, caching, producing textures on demand).
- **Protocols:** Standardize on `PerceptionDevice` (`infer(_:)`) for device lifecycle + inference entrypoint.

Device Streams are **low-level evidence**. Higher-level “Scene State” summaries (e.g., edit safety ratings) are derived from these streams.

## Architectural Mandate (Sensors Edition)
Sprint 24a devices must uphold the non-negotiables:
- **Deterministic** outputs for identical inputs.
- **Edit‑Grade Stable** streams (no flicker/churn without being explicitly surfaced).
- **Explicit uncertainty** (warnings + stability metrics; never silent degradation).

### Confidence governance (Device-level)
Devices must standardize on the shared confidence ontology (MetaVisCore) and may only emit **EvidenceConfidence**.

Requirements:
- Devices emit `EvidenceConfidence` using a shared confidence record (conceptually `ConfidenceRecord.v1`).
- Devices emit finite, sorted reason codes (no free-text).
- Devices must never emit **DecisionConfidence** (policies live above devices in Scene State).

### Device Streams Are Sacred
Devices:
- produce evidence
- expose metrics
- emit warnings deterministically
- never interpret intent

Interpretation (Edit Safety, AutoCut, “who matters”) belongs above the device layer.

## Deliverables

## Status (Confirmed in-code)

### Confirmed implemented
- Tier 0 devices exist and are exercised by deterministic real-video tests:
    - `MaskDevice` (Vision foreground/person segmentation) outputs `kCVPixelFormatType_OneComponent8`.
    - `TracksDevice` (Vision tracking) is implemented and tested.
    - `FlowDevice` (Vision optical flow) is implemented and outputs `kCVPixelFormatType_TwoComponent16Half` (16F).
    - `DepthDevice` is implemented with explicit missing/invalid semantics; tested with missing + synthetic depth buffers.
- Stability contract is implemented at the device layer:
    - `MaskDevice` computes warp-based `stabilityIoU` (mask[t] vs warp(mask[t-1]) on a downscaled grid).
    - Instability is surfaced explicitly via governed reason codes (e.g. `mask_unstable_iou`).
- Sampling strategy is implemented:
    - `MaskDevice.Options.Mode.keyframes(strideSeconds:)` propagates between keyframes using flow warps.
- Warning artifacts are surfaced deterministically:
    - `MasterSensorIngestor` emits device-derived warning segments for stability/track events.
- Face parts foundation is implemented (landmarks-first):
    - `FacePartsDevice` uses Vision face landmarks to produce conservative ROI masks and a normalized `mouthRectTopLeft`.
    - A mouth-local whitening pass exists and is tested for strict ROI locality.

### Deferred follow-ups (not required for Sprint 24a acceptance)
- Tier 1: MobileSAM integration is now implemented (including interactive embedding reuse + env-gated correctness tests).
- Face micro-segmentation (dense parsing) remains optional and model-dependent; landmarks-first ROI-local whitening is the shipped contract.
- Depth Asset C: real LiDAR test asset + alignment/relink stability remain blocked on capture availability.


### Model acquisition status (new)
- Repeatable model downloads are now scripted under `scripts/` and normalized into `assets/models/...`:
    - MobileSAM CoreML bundles: `./scripts/download_mobilesam_coreml.sh` → `assets/models/mobilesam/coreml/*`
    - Face parsing CoreML model (Google Drive link from a model zoo): `./scripts/download_face_parsing_coreml.sh` → `assets/models/face_parsing/FaceParsing.*`
- **Important:** This unblocks model acquisition; `MobileSAMDevice` exists (env-gated tests) and `FacePartsDevice` supports best-effort dense parsing when a compatible model is available.

### 1. Tier 0: Apple-Native Foundation (The "Must Ship")
- **Implementation:**
    - **`MaskDevice`:** Wraps `VNGenerateForegroundInstanceMaskRequest`.
    - **`TracksDevice`:** Wraps `VNTrackObjectRequest`.
- **Contract:**
    - Input: `PixelBuffer` (Video Frame).
    - Output: `MaskTexture` (R8Unorm) + `InstanceID` (UInt8).
- **Use Case:** "Subject Lift", "Background Dimming".

### 1b. Tier 0: Depth (LiDAR)
- **Implementation:**
    - **`DepthDevice`:** produces a depth map aligned to the input frame (when available) or produces “missing” metadata.
- **Contract:**
    - Input: `PixelBuffer` (video frame) + optional depth sample + calibration.
    - Output: `DepthTexture` (R16F/R32F, meters) + optional confidence.
- **Use Case:** true occlusion compositing, depth-aware DOF/volumetrics, and stable “subject distance” metadata.

### 2. Tier 1: Promptable "Select Anything" (MobileSAM)
- **Implementation:**
    - Integrate **MobileSAM (TinyViT variant)** via CoreML.
    - **Optimization:** Use `palettize_weights` (Linear 8-bit quantization) for the Transformer encoder.
    - **Split Architecture:**
        - `ImageEncoder` (Run once per keyframe -> ANE).
        - `MaskDecoder` (Run per click -> CPU/GPU).
- **Use Case:** Director tap-to-select editing.

Model note:
- We currently download pre-exported CoreML `.mlpackage` bundles (encoder/prompt/decoder). Optional compilation to `.mlmodelc` is supported via `xcrun coremlc compile`.

### 3. Face Micro-Segmentation (The "Teeth Whitener")
- **Implementation (Option B: ROI-local whitening):**
    - Use **Vision landmarks** to produce `mouthRectTopLeft` + conservative ROI masks.
    - Whitening is driven by ROI locality; dense parsing is optional and may provide **inner-mouth/lips** masks.
- **Fusion:** Fuse with `VNDetectFaceLandmarksRequest` to crop the input ROIs for higher resolution processing.

Treat FaceParts/Teeth as a flagship capability:
- Whitening FX must be provably local (no skin bleed) via ROI isolation + contract tests.
- If dense parsing is used, its derived masks must be stable and must not create outside-ROI bleed.

Note (current implementation): A landmarks-first FaceParts foundation exists today (mouth/eye ROI masks + `mouthRectTopLeft`) and whitening is implemented as an ROI-local imaging pass. Dense semantic teeth segmentation remains pending until a face-parsing model is bundled and wired.

Decision note (Sprint 24a): We are explicitly choosing ROI-local whitening (Option B) over a hard dependency on a “teeth class”.

### Update (2025-12-21): MobileSAM interactive path is now implemented
- `MobileSAMDevice` supports embedding reuse for interactive prompting:
    - Same-frame reuse (same `CVPixelBuffer` instance).
    - Cache-key reuse via caller-supplied `cacheKey` (stable across frame copies).
- A concrete, end-to-end runtime entry point exists via MetaVisLab:
    - `MetaVisLab mobilesam segment ...` reads a frame, runs 1–2 prompts with the same cacheKey, writes masks, and prints `encoderReused`.
    - `MobileSAMSegmentationService` provides a canonical cacheKey builder (`mobilesam|v1|src=...|t=...|WxH`) suitable for future production call sites.
    - `SourceContentHashV1` defines a stable `sourceKey` for local assets (content hash), and MetaVisLab defaults to that scheme for cacheKey generation.

### 4. Stability Policy (The "Anti-Flicker")
- **Logic:** Implement the "Keyframe -> Track -> Warp" state machine in `MaskDevice`.
- **Metric:** Failing if `IoU(frame_t, warp(frame_t-1)) < 0.85`.

Stability is a contract, not a hope:
- Devices must report stability metrics per interval.
- If stability drops below threshold, devices must emit a warning artifact and/or explicit “unstable” metadata.
- Devices must not silently degrade.

Mandate-aligned addition:
- Stability failures must also downgrade device `EvidenceConfidence` with explicit reason codes (e.g. `mask_unstable_iou`, `track_reacquired`).

### 5. Sampling strategy (don’t overpay)
Many downstream uses do not require frame-by-frame inference.
- Prefer **keyframe sampling** (e.g., 2–5 fps) for expensive segmentation.
- Propagate between samples using tracking and flow warps.
- Re-key on shot boundaries or when stability metrics fail.

This strategy is required to make iOS capture + macOS compilation efficient at scale.

## Performance discipline
- Prefer static model shapes.
- Warm models deterministically.
- Keep behavior stable across iPhone/Mac (no “fast mode” behavioral drift).

## Out of Scope
- **Tier 2 (SAM 2 Video):** Research indicates no viable CoreML path exists yet. We will stick to MobileSAM + Optical Flow for now.

## Research
- See `research/RESEARCH_AGGREGATION.md` for ANE optimization summaries.
