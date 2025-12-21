# Awaiting Implementation

## Gaps & Missing Features
- **Higher-fidelity resampling (if required)**: current approach uses deterministic timeline→source time quantization for VFR-like inputs; if higher-fidelity resampling is needed (e.g., frame blending / optical flow / true time-warp), that remains future work.
- **Broader edit coverage**: the current end-to-end sync contract covers a baseline export and a trim-in style edit (source offset). Extending this to more complex edits (move, split, time-remap, multi-clip) is future work.
- **Probe performance/IO**: the sprint plan calls out `DispatchIO` + `F_NOCACHE` as an optimization, but the current probe uses `AVAssetReader` compressed sample reads.
- **Non-file URL sources**: current normalization in `ClipReader` only applies to local file-backed video containers.

## Recommendations
- If sync regressions reappear, add additional E2E fixtures for edit patterns beyond trim-in (e.g., clip move + gap, split + reorder).
- If probe overhead becomes visible in real workflows, add an IO-optimized probe backend behind a feature flag and measure wall time + battery impact.
