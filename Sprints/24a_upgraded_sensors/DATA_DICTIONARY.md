# Data Dictionary: Upgraded Sensors (Sprint 24a)

## Overview
This dictionary defines the "Device Stream" contracts. Unlike `MasterSensors` (which is JSON metadata), these are **High-Throughput, Live-Renderable Types** meant for the GPU Render Graph.

## Confidence & stability (shared contract)
All device streams must surface **EvidenceConfidence** using the shared confidence ontology in `MetaVisCore` (conceptually `ConfidenceRecord.v1`).

Rules:
- Reasons are a **finite enum** (no free-text), sorted, stable.
- EvidenceConfidence must never increase as evidence degrades.
- Instability must be surfaced explicitly (metrics + warnings + reason codes), never silently.

## 1. MaskDevice Stream
**Type:** `MaskStream`
**Format:** `CVPixelBuffer` (One Component 8-bit, `kCVPixelFormatType_OneComponent8`)
**Semantics:**
*   Val `0`: Background.
*   Val `255`: Foreground / Selected Instance.
*   **Optimization:** `.memoryless` on tile memory where possible.

Required metrics (deterministic):
- `coverage` (foreground pixel ratio)
- `stabilityIoU` (warp-IoU against previous keyframe / previous frame)

Required confidence:
- `evidenceConfidence: ConfidenceRecord.v1` (reasons include `mask_unstable_iou` when below threshold)

### Variant: `InstanceMaskStream`
**Format:** `CVPixelBuffer` (8-bit or 16-bit Integer)
**Semantics:** Pixel value `N` corresponds to `InstanceID(N)`.

## 2. FacePartsDevice Stream
**Type:** `FacePartsBuffer`
**Format:** `CVPixelBuffer` (One Component 8-bit)
**Semantics (BiSeNetV2 Mapping):**
| Value | Label | Notes |
| :--- | :--- | :--- |
| 0 | Background | |
| 1 | Skin | Face minus features |
| 2 | Left Eyebrow | |
| 3 | Right Eyebrow | |
| 4 | Left Eye | |
| 5 | Right Eye | |
| 6 | Glasses | If detected |
| 7 | Left Ear | |
| 8 | Right Ear | |
| 9 | Nose | |
| 10 | Mouth | General mouth area |
| 11 | Upper Lip | |
| 12 | Lower Lip | |
| 13 | Neck | |
| 14 | Necklace | |
| 15 | Cloth | Clothing |
| 16 | Hair | |
| 17 | Hat | |
| **18** | **Teeth** | **Critical for Whitening FX** |

Required metrics (deterministic):
- `roiCoverageOutsideMouth` (teeth/mouth pixels outside mouth ROI)
- `temporalStability` (class stability across frames or samples)

Required confidence:
- `evidenceConfidence: ConfidenceRecord.v1` (reasons include `teeth_outside_mouth_roi` when violated)

## 3. TracksDevice Stream
**Type:** `TrackStream`
**Format:** `[TrackID: NormalizedRect]` (Swift Struct)
**Semantics:**
*   `TrackID`: `UUID` (Stable over time).
*   `NormalizedRect`: `CGRect` (0..1).

Required metrics (deterministic):
- `trackCount`
- `reacquireEvents` (count / intervals)

Required confidence:
- `evidenceConfidence: ConfidenceRecord.v1` (reasons include `track_reacquired` when reacquisition occurs)

## 4. FlowDevice Stream (Optical Flow)
**Type:** `FlowBuffer`
**Format:** `CVPixelBuffer` (Two Component Float16 or Float32, `kCVPixelFormatType_TwoComponent16Half`)
**Semantics:**
*   `R`: Delta X (pixels or normalized).
*   `G`: Delta Y.
*   Used for warping masks forward.

Required confidence:
- `evidenceConfidence: ConfidenceRecord.v1` (reasons include `flow_unstable` if warp error is high)

## 5. DepthDevice Stream (LiDAR / Depth)
**Type:** `DepthStream`

### Depth Map
**Format (preferred):** `CVPixelBuffer` (single-channel Float16/Float32 depth)
**Semantics:**
*   Value is **metric depth in meters** in camera space (aligned to the RGB frame).
*   Missing/invalid depth should be represented explicitly (e.g., NaN) and surfaced as metadata.

Required metrics (deterministic):
- `validPixelRatio`
- `minDepthMeters` / `maxDepthMeters` (excluding invalid pixels)

Required confidence:
- `evidenceConfidence: ConfidenceRecord.v1` (reasons include `depth_missing`, `depth_invalid_range`)

### Confidence (optional)
**Type:** `DepthConfidenceStream`
**Format:** `CVPixelBuffer` (one-component 8-bit)
**Semantics:**
*   `0`: unknown/invalid
*   `255`: high confidence

### Calibration (required for relink + resampling)
**Type:** `DepthCalibration`
**Fields (conceptual):**
*   `intrinsics`: 3x3
*   `referenceDimensions`: width/height that intrinsics are defined against
*   `extrinsicsDepthToRGB` (if depth is captured in a different sensor frame)
*   `timestampDomain`: ties depth samples to `Time`

### Render format mapping
At render time, depth is typically uploaded as a single-channel float texture:
*   `.r16Float` (fast, enough precision for many effects)
*   `.r32Float` (reference / analytics)
