# Sprint 21 — TDD Plan (VFR Normalization + Sync)

## Tests (write first)

### 1) `VFRGeneratedFixtureTests.test_generated_vfr_fixture_is_detected_as_vfr_likely()`
- Use ffmpeg to generate a short MP4 from still frames with varying per-frame durations.
- Run `VideoTimingProbe.probe(url:)`.
- Assert `isVFRLikely == true` and deltas show variability.

### 2) `VFRNormalizationExportE2ETests.test_export_normalizes_vfr_to_target_cfr_timebase()`
- Build a timeline from the generated VFR fixture.
- Export at 24fps.
- Assert `VideoQC` expectations (duration range, sample count, resolution).
- Start as `XCTSkip` until full normalization pipeline exists (no flakes).

### 3) `VFRSyncContractE2ETests.test_edits_preserve_av_sync_with_marker_track()`
- Generate fixture with audio impulses aligned to visual color changes.
- Apply edits (trim/move) to the clip.
- Export and detect alignment within tolerance.
- Start as `XCTSkip` until marker detection helpers exist.

## Production steps
1. Land deterministic VFR fixture generation test.
2. Add export test gated behind implementation.
3. Implement timebase normalization/resampling and sync strategy until export test passes.

## Definition of done
- At least one deterministic VFR fixture test passes in CI.
- Export + sync tests exist and can be enabled once implementation lands.
