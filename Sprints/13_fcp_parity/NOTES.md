# Sprint 13 — Notes (FCP Basics Parity)

## Purpose
This file is a running capture of:
- FCP “basic editor” behaviors we want to match eventually
- items explicitly out of scope for Sprint 13
- known implementation/testing gaps discovered during deep dives

It complements `PLAN.md` and `TDD_PLAN.md` by keeping the backlog visible without expanding sprint scope.

## FCP basics we are *not* tackling in Sprint 13
- Magnetic timeline (connected clips, primary storyline rules, auditions)
- Compound clips / nested timelines
- Multicam
- Sync tooling (auto sync by waveform/timecode)
- Roles-based mixing and organization
- Keyframe automation lanes (opacity/volume/pan), bezier curves, per-parameter animation
- Skimming UX, waveform UI, audio meters UI
- Advanced transitions library and generator effects
- Captions/subtitles pipeline

## Implementation gaps (current repo)
### Timeline/editing semantics
- No first-class editing engine for ripple/roll/slip/slide invariants.
- Blade/split operation not implemented as a typed command.
- Retime is represented as a clip effect (`mv.retime`) but lacks end-to-end semantic verification.

### Video time mapping
- Procedural `ligm://video/...` sources generally do not honor `Clip.offset` and may not be fully time-parametric.
- `TimelineCompiler` is frame-based and only compiles video tracks; audio is rendered separately.

### Audio pipeline
- File-backed audio playback is not implemented (non-`ligm://` audio sources currently return nil).
- Deterministic procedural sources exist; they must remain faithful and covered by unit + E2E tests.
- Export path converts non-interleaved float buffers into interleaved `CMSampleBuffer` via copies; correct but potentially expensive.

## Testing gaps (what we should add as we approach parity)
### Semantic probes
- Video probe: deterministic per-frame fingerprint/luma-stat probe for time mapping + compositing correctness.
- Audio probe: windowed peak/RMS (already useful); optionally add frequency-domain checks for tones/sweeps.

### Editing E2E coverage (FCP-like operations)
- Move: verify content shifts at fixed timeline times.
- Trim-in/out: verify time mapping changes (including `offset` for slip).
- Blade/split: continuity around split point.
- Ripple trim: downstream clips shift deterministically.
- Retime: time mapping changes with measurable effect in both video and audio.

### Stress + determinism
- Seeded random timeline generator (many tracks/clips/overlaps/transitions/offsets).
- Seeded random edit sequence generator (apply K edits deterministically).
- Determinism checks: export twice and assert probes match (within tolerance where needed).

## Triage: high-value next steps
- Add video probe utility and incorporate it into the Sprint 13 E2E matrix.
- Add typed editing commands for blade + ripple trim + move/trim/retime generalized beyond “first clip”.
- Add “procedural video sources honor time/offset” or add new procedural sources designed for time-mapping tests.
