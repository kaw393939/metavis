# Sprint 21 — VFR Normalization + Edit-Aware A/V Sync

## Goal
Turn the existing VFR probe + normalization policy into a **real pipeline** with a testable contract:
- deterministic CFR timebase selection
- deterministic mapping from timeline time → source time
- edit-aware audio/video sync preservation

## Acceptance criteria
- **Deterministic VFR fixture** exists (generated via ffmpeg during tests) and is detected as VFR-likely by `VideoTimingProbe`.
- **Normalization contract**: exporting a timeline built from the VFR fixture produces a CFR deliverable meeting expectations (duration, sample count, fps).
- **Sync contract**: a deterministic audio marker aligns with a deterministic video event within a small tolerance after edits (trim/move).

## Existing code likely touched
- Sources/MetaVisIngest/Timing/VideoTimingProbe.swift
- Sources/MetaVisIngest/Timing/VideoTimingNormalization.swift
- Sources/MetaVisSimulation/ClipReader.swift (time mapping)
- Sources/MetaVisExport/VideoExporter.swift (timeline/export timebase)

## New code to add
- Tests/MetaVisIngestTests/VFRGeneratedFixtureTests.swift
- Tests/MetaVisExportTests/VFRNormalizationExportE2ETests.swift (may be gated until implementation)

## Deterministic data strategy
- Generate a short “VFR still sequence” MP4 using concat demuxer + per-frame durations.
- Optionally include a simple audio tone/impulse at known times.

## Test strategy
- Unit tests for probe/decision logic.
- Integration/E2E test for export + sync (may start as `XCTSkip` until pipeline is implemented).
