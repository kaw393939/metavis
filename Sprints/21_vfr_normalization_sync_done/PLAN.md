# Sprint 21 — VFR Normalization + Edit-Aware A/V Sync

## Goal
Turn the existing VFR probe + normalization policy into a **real pipeline** with a testable contract:
- deterministic CFR timebase selection
- deterministic mapping from timeline time → source time
- edit-aware audio/video sync preservation

## Acceptance criteria
- **Deterministic VFR fixture** exists (generated via ffmpeg during tests) and is detected as VFR-likely by `VideoTimingProbe`.
- **Normalization contract**: exporting a timeline built from the VFR fixture produces a CFR deliverable meeting expectations.
- **Sync contract**: a deterministic audio marker aligns with a deterministic video event within a small tolerance after edits (trim/move).

## Notes
- As of Dec 2025, the core contracts are implemented and covered by end-to-end tests (see “Where to look”).
- The sync contract currently covers baseline + trim-in (source offset) edits. Broader edits (move/split/retime/multi-clip) remain future work.

## Where to look (current code)
- VFR probe heuristic: `Sources/MetaVisIngest/Timing/VideoTimingProbe.swift`
- Normalization policy (decision layer): `Sources/MetaVisIngest/Timing/VideoTimingNormalization.swift`
- Deterministic time mapping (timeline → source) via quantization: `Sources/MetaVisSimulation/ClipReader.swift`
	- Applies only to local video containers (`mov/mp4/m4v`) and caches a per-asset decision.
- Export trace visibility (logs decisions but does not enforce): `Sources/MetaVisSession/ProjectSession.swift` (`traceVFRDecisionsIfNeeded`)

## Where to look (current tests)
- VFR fixture generation + detection: `Tests/MetaVisIngestTests/VFRGeneratedFixtureTests.swift`
- Export normalization contract (output looks CFR-like): `Tests/MetaVisExportTests/VFRNormalizationExportE2ETests.swift`
- Edit-aware sync marker contract (baseline + trim-in): `Tests/MetaVisExportTests/VFRSyncContractE2ETests.swift`
- Quantization correctness for common rates (23.976/29.97/etc): `Tests/MetaVisSimulationTests/VFRTimingQuantizationTests.swift`

## Gaps (what’s still missing)
- **Broader edit coverage**: move, split, gap, overlap/crossfade, multi-clip, mixed FPS sources.
- **Time-remap/retime semantics**: current approach quantizes requested timeline time; it does not implement true resampling/blending/optical flow.
- **Robustness for short clips**: `VideoTimingProbe` intentionally requires enough samples; short sources may be treated as CFR-likely.
- **Non-file URLs / remote sources**: `ClipReader` only normalizes for local file-backed video.
- **Performance/IO**: no `DispatchIO`/`F_NOCACHE` fast-path is implemented; the probe still uses `AVAssetReader` compressed sample reads.

## Plan (if we extend this sprint)
1. Add E2E tests for additional edits (move + gap, split + reorder) using the same deterministic red→green + marker strategy.
2. Add a multi-clip stress test: 2–3 VFR clips + transitions + marker(s) to ensure no sync drift.
3. Add a short-clip fixture (few samples) and document/decide expected behavior (treat as passthrough vs force normalize).
4. Optional perf pass: implement an IO-optimized probe backend (e.g., `DispatchIO`/`F_NOCACHE`) behind a feature flag, keeping the current `AVAssetReader` path as the default.
