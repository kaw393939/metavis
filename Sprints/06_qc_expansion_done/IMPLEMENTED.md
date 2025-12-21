# Implemented Features

## Status: Implemented

## Accomplishments
- **Three-layer QC**: `VideoQC`, `VideoContentQC` (Metal-based), and `VideoMetadataQC` implemented.
- **Integration**: Wired into `ProjectSession.exportDeliverable`.
- **Metrics**: Captures structural, content (fingerprints + color stats), and metadata metrics in manifest.
- **Sidecar QC**: Sidecars are validated (presence + non-empty bytes) and recorded in `qcSidecarReport`.
- **Policy Hooks**: Export supports optional QC policy overrides so callers can enforce thresholds when desired.

## Tests
- `Tests/MetaVisExportTests/QCExpansionE2ETests.swift`
- `Tests/MetaVisPerceptionTests/VideoAnalyzerTests.swift`
