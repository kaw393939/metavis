# Sprint 06 — TDD Plan (QC Expansion)

## Tests (write first)

### 1) `QCExpansionE2ETests.test_deliverable_manifest_embeds_content_qc_metrics()`
- Location: `Tests/MetaVisExportTests/QCExpansionE2ETests.swift`
- Steps:
  - Export a deliverable bundle with a known procedural clip (or reuse `StandardRecipes.SmokeTest2s()`).
  - Run the expanded QC pipeline during export.
  - Assert `deliverable.json` contains:
    - Structural report (already present)
    - Content QC metrics (e.g., mean luma, low/high luma fractions, peak bin, mean RGB) for at least 1 sampled frame
    - Sidecar QC results when sidecars are requested

### 2) `QCMetadataTests.test_export_metadata_color_primaries_transfer_are_recorded_when_available()`
- Location: `Tests/MetaVisExportTests/QCMetadataTests.swift`
- Steps:
  - Export a short clip.
  - Extract track format description metadata where available.
  - Assert the QC report records the values (or explicitly records "unknown" deterministically).

### 3) `VideoAnalyzerDeterminismTests.test_histogram_is_stable_for_synthetic_buffer()`
- Location: `Tests/MetaVisPerceptionTests/VideoAnalyzerDeterminismTests.swift`
- Steps:
  - Create a small deterministic BGRA `CVPixelBuffer` (e.g., 16x16 solid color + stripe).
  - Run `VideoAnalyzer.analyze(pixelBuffer:)`.
  - Assert exact histogram + average color values.

## Production steps
1. Define an expanded QC report model that can embed content+metadata+sidecar metrics.
2. Wire `VideoContentQC` into the deliverables export path (keep deterministic sampling).
3. Implement metadata extraction (graceful fallback).
4. Implement sidecar presence/requirements validation.

## Definition of done
- Expanded QC runs deterministically and is validated end-to-end via deliverable export.
- `deliverable.json` remains backward-compatible and includes the new metrics.
