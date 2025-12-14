# Sprint 13 — FCP Basics Parity (Editing + Tests)

## Goal
Close the gap between MetaVis “renderable timeline” and a basic NLE (Final Cut Pro-style) editing experience.

Focus is *basics-first*: the core edit operations and correctness properties that must hold for real projects, plus meaningful, deterministic E2E tests that expose edge cases.

## Scope (FCP basics)
We target the following baseline capabilities:
- Assemble: multiple video + audio tracks, overlapping clips, deterministic compositing/mixing.
- Edit operations (deterministic):
  - Move clip (change `startTime`)
  - Trim out (change `duration`)
  - Trim in / slip (change `offset`)
  - Blade/split (split one clip into two)
  - Ripple trim (preserve adjacency by shifting downstream clips)
  - Retime (speed) with deterministic time mapping
- Transitions:
  - Fade in/out (clip transitions)
  - Crossfade between adjacent clips
- Audio basics:
  - Non-silent audio export when audio exists
  - Deterministic procedural sources for tests (tone/noise/sweep/impulse)
  - Deterministic envelope behavior during transitions

## Non-goals (explicitly out of scope)
These are core FCP features, but not required for this sprint:
- Magnetic timeline, connected clips, auditions, compound clips
- Multicam, synchronization tooling, role-based mixing
- Keyframe automation lanes (opacity/volume/pan)
- Advanced audio processing (ducking, EQ automation, denoise beyond simple presets)
- Asset management/ingest UX

## Current state (as of 2025-12-13)
### What we already implement
- Timeline model: `TrackKind` (`.video/.audio`), `Track`, `Clip` (`startTime`, `duration`, `offset`, `transitionIn/out`, `effects`).
- Video compile/render: `TimelineCompiler` compiles active video clips per frame; supports transitions and multi-layer compositing.
- Export/QC: `VideoExporter` exports MOV+AAC; `VideoQC` validates container and has an audio non-silence check.
- Intent tools observability (Sprint 08): `TraceSink` + `InMemoryTraceSink` + deterministic intent→commands execution and export tracing.

### Known gaps discovered in deep dive
- Editing operations are not first-class: we don’t have a deterministic “editing engine” that implements blade/ripple/roll/slide semantics.
- Video trim-in (`offset`) is only applied for file-backed sources; procedural video sources (`ligm://video/...`) generally ignore offset/time mapping.
- Audio file-backed playback is stubbed (non-`ligm://` audio sources return nil); procedural-only audio is implemented.
- Historically, some procedural audio URLs were not faithfully implemented (pink/sweep/impulse); these need locked-down tests.
- Stress-level compositing and time mapping correctness are not sufficiently probed (we often validate container/QC but not semantic correctness).

## Acceptance criteria
### Editing correctness (must-have)
- Implement deterministic edit operations (as typed commands) for:
  - move, trim-out, trim-in (offset/slip)
  - blade/split
  - ripple trim (at least ripple trim-out)
  - retime
- Each operation has E2E tests that validate *observable media changes* (not just “export succeeds”).

### Parity probes (must-have)
- Audio probes: decode exported audio and compute peak/RMS over time windows.
- Video probes: deterministic per-frame probe (e.g. sample pixels / fingerprint / luma stats) to assert time mapping + compositing semantics.

### Stress tests (must-have)
- A small suite of deterministic stress E2E tests exists for:
  - audio-only editing
  - video-only editing
  - combined A/V editing
  - “many clips/tracks/overlaps” edge cases
- Stress tests must be deterministic (seeded) and reproducible.

## Deterministic test media strategy
- Procedural sources only (no external files) for baseline coverage:
  - Video: SMPTE, Macbeth, zone plate, counter (already present)
  - Audio: sine, white noise, pink noise, sweep, impulse (must be faithful)
- Tests should validate time-mapping semantics by sampling at specific windows:
  - e.g. “tone moves earlier after edit”, “impulse shifts with offset”, “retime changes per-window energy.”

## Work breakdown
1. Define a minimal “editing command” surface area (typed commands) that maps to the Timeline model.
2. Implement edit operations with clear invariants and deterministic behavior.
3. Add video probes (frame sampling/fingerprint) and audio probes (peak/RMS) for assertions.
4. Add E2E test matrix:
   - audio-only / video-only / A/V
   - each operation: move, trim in/out, blade, ripple, retime
5. Add deterministic stress generators (seeded) to produce complex timelines and apply randomized edit sequences.

## References (existing files)
- Timeline model: `Sources/MetaVisTimeline/Timeline.swift`, `Sources/MetaVisTimeline/Transition.swift`
- Video compile: `Sources/MetaVisSimulation/TimelineCompiler.swift`
- Export/QC: `Sources/MetaVisExport/VideoExporter.swift`, `Sources/MetaVisQC/VideoQC.swift`
- Intent tools observability: `Sources/MetaVisCore/Tracing/Trace.swift`, `Sources/MetaVisSession/Commands/*`
- Existing export E2E: `Tests/MetaVisExportTests/*`
