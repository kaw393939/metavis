# Sprint 24i — Measurement Checklist

This sprint’s acceptance requires at least one measurable win on Apple M3+ for a representative graph, without changing effect semantics.

## What to measure (repeatable)
- Tests/MetaVisSimulationTests/Perf/RenderPerfTests.swift
  - Wall-clock avg ms per frame (engine submit + GPU completion).
  - Enable logging with METAVIS_PERF_LOG=1.
- Tests/MetaVisSimulationTests/Perf/RenderMemoryPerfTests.swift
  - Peak RSS delta budget (guards runaway allocations / pooling regressions).

## How to run
- Render time budget test (prints avg when logging enabled):
  - METAVIS_PERF_LOG=1 METAVIS_RENDER_FRAME_BUDGET_MS=400 swift test --filter RenderPerfTests/test_render_frame_budget
- Memory budget test:
  - METAVIS_RENDER_PEAK_RSS_DELTA_MB=1024 swift test --filter RenderMemoryPerfTests/test_render_peak_rss_delta_budget

## Automated perf logging
When `METAVIS_PERF_LOG=1`, perf tests also write a structured JSONL log into `test_outputs/` (gitignored).

- Default log path:
  - `test_outputs/perf/perf.jsonl`
- Override log path:
  - `METAVIS_PERF_LOG_PATH=/absolute/or/relative/path/to/perf.jsonl`
- Optional run ID (useful for grouping):
  - `METAVIS_PERF_RUN_ID=20251223_local_m3`

## Resolution sweep (common resolutions + optional 8K)
Runs the representative graphs across common resolutions and records failures/skips so we can see where performance or allocation breaks.

- Run sweep:
  - `METAVIS_RUN_PERF_SWEEP=1 METAVIS_PERF_LOG=1 swift test --filter RenderPerfTests/test_render_perf_sweep_common_resolutions_opt_in`

### Reduce noise (repeat runs)
- Repeat each sweep cell N times:
  - `METAVIS_PERF_SWEEP_REPEATS=3`

### Sweep render policy tiers (consumer/creator/studio)
By default the sweep runs only the `creator` tier to keep runtime manageable. To run all tiers:
- `METAVIS_PERF_SWEEP_POLICIES=1`
- Optional: choose a subset/order:
  - `METAVIS_PERF_SWEEP_POLICY_TIERS=consumer,creator,studio`

One-command helper:
- `scripts/run_perf_sweep_policies.sh 3`
- Include 8K (4320p / 7680×4320):
  - `METAVIS_RUN_PERF_8K=1`
- Limit max height for quick sanity (e.g., only 360p):
  - `METAVIS_PERF_SWEEP_MAX_HEIGHT=360`
- Override frames per resolution:
  - `METAVIS_PERF_FRAMES=12`
- Fail the test if any sweep case errors:
  - `METAVIS_PERF_SWEEP_STRICT=1`
- Safety valve (skip runs with huge estimated working set):
  - `METAVIS_PERF_MAX_EST_TEXTURE_MB=1500` (default)
  - `METAVIS_PERF_DISABLE_ESTIMATE_SKIP=1` (force attempt)

## Representative graphs to capture in Xcode
Use Xcode’s GPU tools on M3+ for deeper attribution (bandwidth / occupancy / threadgroup efficiency):
- Single source procedural: SMPTE → output
- Blur chain: SMPTE → blur_h → blur_v
- 2-clip transition: compositor_* (when available in a minimal graph)
- Masked blur: input → fx_masked_blur (mask path)

## Evidence to record (notes only)
- Before/after numbers from the perf tests.
- For the kernel you changed: GPU Frame Capture notes (kernel duration, threadgroup size, texture formats).
