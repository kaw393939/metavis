# Sprint 6 Audit: QC Expansion

## Status: Implemented

## Accomplishments
- **VideoMetadataQC**: Implemented and extracts FourCC, color primaries, transfer functions, and HDR status.
- **VideoQC**: Implemented and validates duration, resolution, frame rate, and sample count.
- **VideoContentQC**: Implemented and uses Metal-accelerated fingerprints and color stats.
- **Integration**: `ProjectSession.exportDeliverable` correctly triggers all three QC layers and populates the `DeliverableManifest`.

## Verified additions
- **Sidecar generation**: captions and image sidecars are generated (best-effort copy when available, otherwise render minimal valid outputs).
- **Sidecar QC**: requested vs written sidecars + byte sizes are recorded in `qcSidecarReport`.

## Gaps & Missing Features
- **QC Policy Enforcement**: While `VideoQC` throws on failure, `VideoMetadataQC` and `VideoContentQC` currently just report data. There's no policy-driven "fail if not HDR" or "fail if average brightness < X".

## Tests
- `Tests/MetaVisExportTests/QCExpansionE2ETests.swift`
- `Tests/MetaVisPerceptionTests/VideoAnalyzerTests.swift`

## Performance Optimizations
- **GPU Acceleration**: QC already uses Metal for fingerprints and color stats, which is excellent.
- **Sampling Strategy**: Currently uses fixed 10%, 50%, 90% points. Could be optimized to sample based on timeline markers or scene changes.

## Low Hanging Fruit
- Add basic "Expectations" to `VideoMetadataQC` (e.g., `expectedCodec`).
