# Sprint 11 — TDD Plan (Golden + Perf)

## Tests (write first)

### 1) `GoldenFrameHashTests.test_smpte_frame_hash()`
- Render SMPTE generator frame at fixed resolution.
- Downsample deterministically.
- Hash bytes and compare to expected.

### 2) `GoldenFrameHashTests.test_zone_plate_hash()`
- Same as above for zone plate.

### 3) `RenderPerfTests.test_render_frame_budget()`
- Use `measure {}` to render N frames.
- Record baseline and enforce a ceiling with guardrails (budget may be different for CI).

### 4) `ExportPerfTests.test_export_clip_budget_and_no_cpu_readback()`
- Export a short deterministic clip.
- Assert throughput budget (pragmatic ceiling).
- Assert exporter path does not use CPU readback for standard formats (guardrails; implementation-dependent).

### 5) `RenderAllocationTests.test_multipass_has_no_steady_state_texture_allocations()`
- Render enough warmup frames to reach steady state.
- Assert per-frame allocation counters remain at 0 (or under a tight bound) once warmed.

## Production steps
1. Add `FrameHashing` helper for deterministic downsample + hash.
2. Add golden tests.
3. Add perf tests with pragmatic budgets.
4. Add export perf + allocation guardrails (ties into `TexturePool`/export zero-copy work).

## Definition of done
- Golden tests catch visual regressions deterministically.
- Perf tests provide early warning without flakiness.
