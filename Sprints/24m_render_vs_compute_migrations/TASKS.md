# Sprint 24m — TASKS

## Goal
Move work that should be tile-local out of compute where the research indicates large bandwidth savings.

## 1) Compositor (tile-memory / programmable blending)
- [ ] Profile compositor kernels in representative multi-layer graphs (1080p/4K/8K).
- [ ] Implement render pipeline path for highest-frequency blends (source-over / crossfade first).
- [ ] Keep compute compositor as a fallback behind a feature flag.
- [ ] Validate with `Tests/MetaVisExportTests/TransitionDipWipeE2ETests.swift`.

## 2) ClearColor (deprecate compute clear)
- [ ] Identify any remaining `ClearColor.metal` usage in hot paths.
- [ ] Replace with render-pass `MTLLoadAction.clear` where possible.
- [ ] Verify "clear-only" perf graphs do not regress.

## 3) DepthOne (attachment clear)
- [ ] Replace compute-based depth clears with depth attachment loadAction clear.
- [ ] Ensure semantics match existing depth usage.

## Acceptance
- [ ] Multi-layer compositing is faster (bandwidth down).
- [ ] Cleared attachments no longer dispatch compute.
- [ ] Fallback compute paths remain available.
