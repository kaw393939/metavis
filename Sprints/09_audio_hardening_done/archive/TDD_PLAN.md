# Sprint 09 — TDD Plan (Audio Hardening)

## Tests (write first)

### 1) `AudioE2ETests.test_export_contains_non_silent_audio()`
- Location: `Tests/MetaVisExportTests/AudioE2ETests.swift`
- Steps:
  - Build timeline with deterministic audio content (tone) and a simple video generator.
  - Export 1–2 seconds.
  - Run `VideoQC` with `requireAudio: true`.
  - Assert passes.

### 2) `AudioRendererTests.test_renderer_never_force_unwraps_format()`
- Location: `Tests/MetaVisAudioTests/AudioRendererTests.swift`
- Ensure renderer returns a structured error if format creation fails.

### 3) `AudioMetricsTests.test_peak_rms_deterministic()`
- Decode exported audio and compute peak/RMS; assert within tolerance.

### 4) `DialogCleanwaterE2ETests.test_loudness_normalization_improves_consistency()`
- Builds a deterministic audio clip with varying gain.
- Applies the dialog cleanwater transform.
- Exports and asserts loudness/peak metrics are within a target range.

## Production steps
1. Replace `AVAudioFormat(...)!` usage with safe creation and typed error.
2. Implement deterministic mixing/downmix rules.
3. Ensure exporter uses the same sample rate/channel layout consistently.

## Definition of done
- Audio export is robust and verified end-to-end without mocks.
