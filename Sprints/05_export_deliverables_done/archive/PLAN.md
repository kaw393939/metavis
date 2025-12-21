# Sprint 05 — Export Deliverables Packaging

## Goal
Add a deliverables layer that packages exports as a structured artifact (movie + metadata + optional sidecars) rather than “just a .mov”. Deliverables are the core “output types” a creator chooses (YouTube master, Shorts, review proxy, captions, audio-only).

## Acceptance criteria
- A `Deliverable` concept exists that can produce an export bundle (directory) containing:
  - `video.mov`
  - `deliverable.json` (timeline summary, quality profile, governance summary, QC results)
  - optional sidecars (v1: optional): captions (`.srt`/`.vtt`), thumbnails/contact sheet
- Session/export path can export a deliverable bundle.
- E2E test exports a deliverable bundle and validates:
  - files exist
  - metadata is decodable and internally consistent
  - QC results recorded match deterministic QC output
 - Default export path avoids CPU readback (`texture.getBytes`) by using GPU→`CVPixelBuffer` conversion (prefer 10-bit where supported).

## Existing code likely touched
- `Sources/MetaVisExport/VideoExporter.swift`
- `Sources/MetaVisSession/ProjectSession.swift`
- `Sources/MetaVisQC/VideoQC.swift` (reused)
- `Sources/MetaVisTimeline/*` (timeline summary serialization)

## New code to add
- `Sources/MetaVisExport/Deliverables/ExportDeliverable.swift`
- `Sources/MetaVisExport/Deliverables/DeliverableManifest.swift`
- `Sources/MetaVisExport/Deliverables/DeliverableWriter.swift`

## Alignment note
Deliverables should be policy-driven (Sprint 03) so we can express “deliverables-only uploads allowed” while keeping raw media local by default.

Performance reference: `Docs/research_notes/legacy_autopsy_optimizations_apple_silicon.md`
metavis3 export reference (10-bit + CVMetalTextureCache plane conversion): `Docs/research_notes/metavis3_fits_jwst_export_autopsy.md`

## Existing tests to update
- If any exporter tests assert a single-file output path, update to allow directory outputs for deliverables.

## Deterministic generated-data strategy
- Use procedural video generator timeline (SMPTE/zone plate).
- Use deterministic audio policy: `.includeGenerated` (if/when available) or `.auto` with deterministic audio track.

## Test strategy (no mocks)
- E2E: create timeline → export deliverable bundle → run `VideoQC` → verify manifest contains QC pass results.

## Work breakdown
1. Define deliverable manifest schema.
2. Implement deliverable writer (directory structure + atomic writes).
3. Add session API: `exportDeliverable(...)`.
4. Add E2E tests.

## Export performance follow-ups (capture as backlog items)
- Ensure the exporter avoids CPU readback (`texture.getBytes`) for the default path; prefer GPU→`CVPixelBuffer` zero-copy conversions.
- Add bounded in-flight frames and measure export throughput (ties into Sprint 11 perf budgets).
 - Align pixel buffer formats with Apple Silicon media engine best path (10-bit bi-planar YUV + CVMetalTextureCache plane textures) where supported.
