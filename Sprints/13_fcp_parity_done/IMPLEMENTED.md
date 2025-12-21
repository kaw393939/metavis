# Implemented Features

## Status: Done

## Accomplishments
- **Timeline**: `Clip` supports `startTime`, `duration`, `offset`, `transitionIn/out`, and `effects`.
- **Compiler**: `TimelineCompiler` supports overlapping clips, alpha-based fades/crossfades, and ACEScg working space.
- **Editing Commands**: Deterministic typed commands exist for move, trim-out, trim-in (slip), blade/split, ripple trim-in/out, and ripple delete.
- **Time Mapping**: Video sources use clip-local time for both procedural and file-backed sources.
- **Retime**: `mv.retime` is applied as time-mapping for video sources (observable in exports).
- **Audio Files**: File-backed audio decode/playback exists (in addition to procedural sources).
- **Tests**: Session-level E2E tests cover edit command semantics; export E2E tests include audio probes (peak/RMS) and video probes (fingerprint/color-stats) for deterministic QC.

## Out of Scope (Sprint 13)
- **Transition Types**: `TransitionType.dip` and `.wipe` are modeled but not required for Sprint 13 parity; fades/crossfades only.
