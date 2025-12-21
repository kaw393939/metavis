# Sprint 24a: Upgraded Sensors (The Ideal Package)

## Goal
Implement the **2025 Ideal Sensor Package** to provide the renderer with dense, stable, mask-rich streams for "Hollywood-grade" compositing and color grading.

This sprint also establishes the foundation for the two-product pipeline:
- **iOS Sensor App**: records 1080p proxy + LiDAR/depth sidecars (and optional IMU), then relinks to full-res media later.
- **macOS Director/Compiler**: consumes proxy + sidecars for fast preview, then recompiles against full-res on relink.

## Design Principle
**Everything is a Device Stream.**
- `MaskDevice` (Segmentation)
- `FacePartsDevice` (Teeth/Lips/Skin)
- `FlowDevice` (Motion)
- `DepthDevice` (LiDAR / depth texture)

## Code Integration Strategy (DRY)
We will leverage existing infrastructure to avoid wheel reinvention:
- **Time:** Use `MetaVisCore.Time` (Rational) for all timestamps.
- **Buffers:** Use `CoreVideo.CVPixelBuffer` directly (standard currency in `ClipReader`).
- **Ingest:** Model `MaskDevice` after `ClipReader` (Actor-based, caching, producing textures on demand).
- **Protocols:** Introduce a shared `DeviceProtocol` to standardize `render(time:) -> T`.

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

### 3. Face Micro-Segmentation (The "Teeth Whitener")
- **Implementation:**
    - Train/Convert **`BiSeNetV2`** on `CelebAMask-HQ`.
    - **Output:** Semantic Mask with channels for [Skin, Brows, Eyes, Lips, Teeth, Hair].
- **Fusion:** Fuse with `VNDetectFaceLandmarksRequest` to crop the input ROIs for higher resolution processing.

Treat FaceParts/Teeth as a flagship capability:
- Teeth mask must be spatially consistent and non-flickering.
- Whitening FX must be provably local (no skin bleed) via ROI isolation + contract tests.

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
