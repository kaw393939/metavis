# Sprint 09 — Audio Hardening (Deterministic)

## Goal
Make audio rendering/export robust and deterministic:
- remove unsafe unwraps
- define deterministic mixing/downmix rules
- verify non-silence end-to-end

This sprint also establishes the foundation for “cleanwater” dialog improvements (basic noise reduction + loudness normalization) as deterministic, local-first processing.

## Acceptance criteria
- `AudioTimelineRenderer` has no forced unwraps for format creation.
- Deterministic mixing rules are documented and implemented.
- E2E test exports a clip with deterministic audible content and passes QC non-silence.
- Add at least one deterministic “dialog cleanup” transform (v1: loudness normalization or simple denoise placeholder) with an E2E validation strategy (metrics within tolerance).

## Existing code likely touched
- `Sources/MetaVisAudio/AudioTimelineRenderer.swift`
- `Sources/MetaVisAudio/AudioSignalGenerator.swift`
- `Sources/MetaVisExport/VideoExporter.swift`
- `Sources/MetaVisQC/VideoQC.swift` (non-silence already exists)

## New code to add
- `Sources/MetaVisAudio/AudioMixing.swift` (rules + helpers)
- Optionally: `Sources/MetaVisTimeline/AudioClip.swift` or similar if needed to represent audio events cleanly.

## Deterministic generated-data strategy
- Generate a fixed-frequency tone (e.g. 440 Hz) with deterministic amplitude envelope.
- Ensure exact sample rate and channel count.

## Test strategy (no mocks)
- E2E export of a short clip with audio.
- Validate audio track exists and is non-silent using `VideoQC`.
- Optional: decode audio and assert deterministic peak/RMS within tolerance.
