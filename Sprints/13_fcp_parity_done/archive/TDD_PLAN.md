# Sprint 13 — TDD Plan (FCP Basics Parity)

## Test principles
- No mocks for E2E: use real `MetalSimulationEngine` + `VideoExporter` + `VideoQC`.
- Deterministic: all stress tests must be seeded and produce the same timeline and edits every run.
- Assertions must be semantic: prove media changes (audio peak/RMS windows; video per-frame probes), not just “export succeeded”.

## Test utilities to standardize
### Audio probe (required)
- Decode audio from exported movie and compute:
  - peak (max abs sample)
  - RMS
  - windowed peak/RMS by time range

### Video probe (required)
Choose one deterministic probe and standardize on it:
- Option A: sample N pixels at fixed coordinates and compare hash/fingerprint.
- Option B: decode a frame to CVPixelBuffer and compute luma histogram summary (bin peak + mean).

The probe should be fast and tolerant where necessary (minor encoder differences), but strict enough to detect incorrect time mapping and compositing.

## E2E matrix (minimum viable)
### 1) Video-only editing
**`VideoEditingE2ETests.test_move_clip_changes_probed_frame()`**
- Build a timeline with 2 procedural video clips.
- Export baseline.
- Apply a move edit (shift clip earlier/later).
- Export after.
- Probe a frame at time T and assert the fingerprint changed as expected.

**`VideoEditingE2ETests.test_trim_out_shortens_content_and_qc_passes()`**
- Trim end of first clip.
- Assert expected duration/frame counts and probe at the old end is now “next clip / empty”.

**`VideoEditingE2ETests.test_blade_split_preserves_visual_continuity()`**
- Split a clip at time T into A and B.
- Assert probe before/after the split matches baseline.

### 2) Audio-only editing
**`AudioEditingE2ETests.test_move_audio_clip_shifts_energy_window()`**
- Place a tone late (e.g. starts at 1.0s).
- Export baseline; assert peak window early is ~silent and late is audible.
- Move clip earlier; re-export; assert early is now audible.

**`AudioEditingE2ETests.test_trim_in_offset_shifts_impulse()`**
- Use impulse with interval and apply `offset`.
- Assert peak window shifts to reflect trim-in.

### 3) Combined A/V editing
**`AVEditingE2ETests.test_ripple_trim_shifts_downstream_audio_and_video()`**
- Build a timeline with sequential clips.
- Ripple-trim a first clip shorter.
- Assert that a downstream probe time now maps to content from later in baseline.

**`AVEditingE2ETests.test_retime_changes_audio_and_video_time_mapping()`**
- Apply a retime factor.
- Assert: video probe at a fixed time differs from baseline; audio RMS window changes.

## Stress suites (seeded)
### 4) Timeline stress
**`StressTimelineE2ETests.test_many_tracks_many_overlaps_exports_and_is_finite()`**
- Seeded generator creates:
  - N video tracks with overlapping procedural sources + transitions
  - M audio tracks with overlapping procedural audio + transitions + offsets
- Export and assert:
  - `VideoQC.validateMovie` passes
  - `VideoQC.assertAudioNotSilent` passes when audio required
  - peak/RMS are finite

### 5) Edit-sequence stress
**`StressEditsE2ETests.test_seeded_random_edit_sequence_is_deterministic()`**
- Generate baseline timeline with seed S.
- Apply K edits (move/trim/split/ripple/retime) chosen deterministically from seed.
- Export twice and assert probes match (determinism).

## Implementation notes (to enable tests)
- Editing operations should live as typed commands (similar to Sprint 08 intent commands) and mutate `Timeline` deterministically.
- Prefer local, procedural assets for tests; file-backed sources can be added later once audio file playback is implemented.

## Definition of done
- The E2E matrix exists (video-only, audio-only, A/V) and passes.
- At least 2 stress suites exist and pass deterministically.
- Failures produce actionable signals (probe deltas and trace events when available).
