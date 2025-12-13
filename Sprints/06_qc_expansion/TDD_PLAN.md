# Sprint 06 — TDD Plan (QC Expansion)

## Tests (write first)

### 1) `QCColorTests.test_smpte_bars_luma_metrics_in_range()`
- Location: `Tests/MetaVisQCTests/QCColorTests.swift` (or nearest existing QC test target)
- Steps:
  - Export SMPTE bars clip.
  - Extract a deterministic frame.
  - Compute downsampled luma histogram/mean.
  - Assert within expected ranges.

  Note:
  - Keep this test strictly deterministic (downsample + metrics + optional hash).
  - Any ML/perception-aligned checks should be separate tests using tolerant ranges (no strict hashes).

### 2) `QCMetadataTests.test_export_metadata_matches_quality_profile()`
- Validate fps/resolution/bit depth where APIs permit.

## Production steps
1. Implement metric computation helpers (deterministic).
2. Add QC checks as composable functions.

## Definition of done
- New checks run deterministically and are validated end-to-end.
