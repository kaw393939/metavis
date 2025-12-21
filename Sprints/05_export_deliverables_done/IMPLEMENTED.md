# Implemented Features

## Status: Implemented (Sprint 05 core)

## Acceptance criteria (met)
- ✅ Deliverable bundle directory contains `video.mov` and `deliverable.json`.
- ✅ Manifest is decodable and includes QC/metadata reports.
- ✅ Optional sidecars supported (captions, thumbnails, contact sheets).
- ✅ Batch export supported (multiple deliverables into sub-bundles).

## Accomplishments
- **ExportDeliverable**: Struct for deliverable identity/metadata.
- **DeliverableWriter**: Atomic bundle creation with staging dir and `deliverable.json`.
- **ProjectSession.exportDeliverable**: Orchestrates export → QC → manifest.
- **Sidecar Generation**: Captions + thumbnails/contact sheets via `DeliverableSidecarRequest` and `SidecarWriters`.
- **Batch Export**: `ProjectSession.exportBatch(...)` exports multiple deliverables into sub-bundles.

## Tests
- `Tests/MetaVisExportTests/DeliverableE2ETests.swift`
- `Tests/MetaVisExportTests/DeliverableManifestBackCompatTests.swift`
