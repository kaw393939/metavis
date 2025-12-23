# Sprint 24k — FINDINGS

Record reference-validation results and any behavior changes discovered during implementation.

## Baseline (today)
- ACEScg working-space contract is in place.
- Studio display rendering uses **OCIO-baked ACES 1.3 LUTs** (SDR + HDR PQ1000) applied via GPU `lut_apply_3d`.
- Color correctness is tracked via opt-in tests; perf/memory are tracked via opt-in perf logging.
- A historical results protocol exists under `test_outputs/metrics/`.

## Protocol: record evidence (do this for every optimization)
Preferred command:
- `scripts/run_metrics.sh --run-id <tag>`

Artifacts to attach/link in findings:
- `test_outputs/metrics/<RUN_ID>/summary.md`
- `test_outputs/metrics/<RUN_ID>/swift_test.log`

Optional (reference chain integrity):
- `scripts/run_metrics.sh --run-id <tag> --ocio-ref`

## Evidence log
Add entries as we implement:
- Date / hardware / OS
- Test command(s)
- Reference vs output deltas (ΔE, ramp tint, HDR roll-off notes)
- Any policy-tier deviation notes

### 2025-12-23 — baseline metrics run
- Run id: `local_smoke_20251223T000000Z`
- Command: `scripts/run_metrics.sh --run-id local_smoke_20251223T000000Z`
- Key results (from log):
	- Perf 360p Render: ~0.96ms avg (12 frames)
	- Peak RSS delta: ~24.3MB
	- Macbeth ACEScg(scene) ΔE2000: avg=0.0078 max=0.0172 worst=orange_yellow
	- Consumer SDR display ΔE2000 (informational): avg=4.698 max=9.746 worst=orange_yellow
	- Studio LUT GPU-vs-CPU match: meanAbsErr=0.000216 maxAbsErr=0.001089 worst=bluish_green
