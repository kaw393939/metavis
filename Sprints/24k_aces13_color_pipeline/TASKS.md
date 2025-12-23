# Sprint 24k — TASKS

## Ownership + distribution (holistic)
- 24k owns **color-science correctness**, reference strategy, goldens, and acceptance thresholds.
- 24i owns **shader-level perf refactors** (branchless math, shaper LUTs, per-kernel optimizations) once 24k defines correctness targets.
- 24m owns **render-vs-compute migrations** (tile-memory wins) for compositor/clear/depth.
- 24n owns **QC + scope reductions** (atomics and waveform/scope kernel performance), while 24k owns color correctness.
- 24o owns **volumetric half/quarter-res + upscale** work.

## 1) Assets + provenance
- [ ] Keep `Tests/Assets/acescg/README.md` accurate (provenance + intended use).
- [ ] Add a small set of CTL-derived goldens (SDR + HDR PQ1000).
- [ ] Decide whether to keep ColorChecker 2005 in addition to 2014 (or use both).

## 2) Reference pipeline correctness
- [ ] Implement ACES 1.3 sweeteners (glow, red modifier).
- [ ] Implement Reference Gamut Compression (RGC).
- [ ] Replace default HDR tonemap with ACES 1.3 HDR ODT behavior (PQ 1000 nits).
- [ ] Make PQ/transfer functions branchless where practical.

### 2c) Shader fallback (Option B: analytic approximation)
- [x] Add `METAVIS_FORCE_SHADER_ODT=1` to force shader ODTs (skip LUT) for testing.
- [x] Add `METAVIS_FORCE_SHADER_ODT_TUNED=1` to force the tuned Studio SDR shader ODT (parameterized fallback).
	- Current best-known defaults (SDR ΔE2000 sweep): `gc=0.08 hd=0.06 rm=0.16` (avg≈1.499, max≈2.518).
- [x] Add `METAVIS_FORCE_SHADER_ODT_HDR_TUNED=1` to force the tuned HDR PQ1000 shader ODT (parameterized fallback).
	- Current best-known defaults (HDR Macbeth sweep): `pqScale≈0.136 knee≈10000 gc≈0.00` (meanAbs≈0.01319, maxAbs≈0.05493).
- [x] Upgrade SDR shader fallback ODT to a closer ACES RRT-style fitted curve.
- [x] Improve HDR PQ1000 shader fallback toward ACES 1.3 LUT (fixed incorrect ACEScg→Rec.2020 matrix that was driving the bright/yellow mismatch).
	- Note: Rec.2020 conversion now matches expected AP1(D60)→Rec.2020(D65) behavior.

## 2a) Smooth system integration (do not break shipping defaults)
- [x] Add a display-target selector (SDR default, HDR PQ1000 opt-in).
	- Implementation: `RenderRequest.DisplayTarget` + `TimelineCompiler` selection.
- [x] Add HDR PQ1000 ODT support (shipping-safe).
- [x] Ensure compiler still appends exactly one ODT (graph root).
- [x] Ensure engine prewarms the relevant pipelines (including `lut_apply_3d`).

## 2b) Reference strategy (Studio)
- [x] Adopt official OCIO-baked ACES 1.3 LUTs as the Studio reference for SDR + HDR PQ1000.
- [x] Commit LUT artifacts as SwiftPM resources and load them robustly.
- [x] Add opt-in tests:
	- GPU LUT output vs CPU evaluation of the same LUT (Studio reference match)
	- OCIO re-bake equivalence vs committed artifacts

## 3) Validator tests
- [x] Add ColorChecker patch sampler + ΔE tests.
- [ ] Add grayscale ramp tint + banding tests.
- [x] Add HDR ramp tests for highlight roll-off (shader-vs-LUT parity ramp).
- [x] Add opt-in shader-vs-LUT parity tests (Macbeth patches, SDR + HDR) for fallback optimization.

## 4) Tier bounds (policy)
- [ ] Define tolerances vs `studio` outputs.
- [ ] Add tier-sweep validator tests for `consumer/creator/studio`.

## 4b) Repeatable perf+color protocol (historical)
- [x] One-command runner to gather perf + memory + color-cert.
	- `scripts/run_metrics.sh` → `test_outputs/metrics/<RUN_ID>/summary.md`
- [x] Ensure key color metrics are recorded in `test_outputs/perf/perf.jsonl` (runID-tagged).
- [x] Add LUT-vs-shader ODT perf comparison (GPU node timings) for SDR + HDR.
	- Test: `Tests/MetaVisSimulationTests/ACESODTPerformanceComparisonTests.swift`
	- Perf helper: `METAVIS_SKIP_READBACK=1` to avoid CPU readback during perf runs.

## 5) Real-world integration
- [ ] Add an ingest smoke test for `Tests/Assets/VideoEdit/apple_prores422hq.mov`.
- [ ] Require explicit ingest profile selection in the test (no “auto mystery”).
- [ ] Load ingest declarations from `Tests/Assets/VideoEdit/apple_prores422hq.mov.profile.json`.

## 6) Performance optimization (1080p / 4K / 8K)
- [ ] Establish policy-tier baselines:
	- `scripts/run_metrics.sh --perf-sweep --sweep-repeats 3`
	- Save run IDs for before/after comparisons.
- [ ] Identify top GPU costs at 1080p/4K/8K (per-stage when available).
- [ ] Apply tiered optimization rules:
	- `consumer`: minimize passes and bandwidth; allow lower precision where safe.
	- `creator`: balanced; prefer stable quality at interactive framerates.

## Distributed work (tracked in other sprints)
- 24i: branchless transfer functions, ACES helper refactors, LUT/shaper optimizations, per-kernel perf work.
- 24m: compositor/clear/depth render-pipeline migrations.
- 24n: QC fingerprint atomic reductions + waveform/scope kernel reductions.
- 24o: volumetric half/quarter-res + upscale (MetalFX).
	- `studio`: keep reference fidelity; optimize implementation without changing look.
