# Sprint 24i — Findings Log (Living)

This file is the running log of perf work for 24i. Keep entries small and factual.

## Current baseline
- Date: 2025-12-22
- Machine: MacBook Air (Mac15,1), Apple M3, 16 GB
- OS: macOS 26.0.1 (25A362)
- Xcode: Xcode 26.2 (17C52)
- Notes (power mode, external display, etc.):

### RenderPerfTests baseline
- Command:
  - `METAVIS_PERF_LOG=1 swift test --filter RenderPerfTests/test_render_frame_budget`
- Avg ms/frame: 0.76ms (12 frames @ 640×360)
- Budget ms/frame (if set):

### RenderPerfTests extended (opt-in representative graphs)
- Blur chain (SMPTE → `fx_blur_h` → `fx_blur_v`)
  - Command:
    - `METAVIS_RUN_EXTENDED_PERF=1 METAVIS_PERF_LOG=1 swift test --filter RenderPerfTests/test_render_perf_blur_chain_opt_in`
  - Avg ms/frame: 1.20ms (12 frames @ 640×360)
- Masked blur (`source_test_color` + mask → `fx_masked_blur`)
  - Command:
    - `METAVIS_RUN_EXTENDED_PERF=1 METAVIS_PERF_LOG=1 swift test --filter RenderPerfTests/test_render_perf_masked_blur_opt_in`
  - Avg ms/frame: 1.53ms (12 frames @ 640×360)
- Compositor crossfade
  - Command:
    - `METAVIS_RUN_EXTENDED_PERF=1 METAVIS_PERF_LOG=1 swift test --filter RenderPerfTests/test_render_perf_compositor_crossfade_opt_in`
  - Avg ms/frame: 1.09ms (12 frames @ 640×360)

### RenderMemoryPerfTests baseline
- Command:
  - `swift test --filter RenderMemoryPerfTests/test_render_peak_rss_delta_budget`
- Peak RSS delta (MB): 22.2 MB
- Budget (MB, if set):

## 2025-12-23 — Resolution sweep (through 8K)
- Command:
  - `METAVIS_RUN_PERF_SWEEP=1 METAVIS_RUN_PERF_8K=1 METAVIS_PERF_LOG=1 swift test --filter RenderPerfTests/test_render_perf_sweep_common_resolutions_opt_in`
- Summary (avg ms/frame):
  - 360p (640×360): Render 0.78, Crossfade 1.03, BlurChain 0.77, MaskedBlur 0.84
  - 720p (1280×720): Render 0.82, Crossfade 1.28, BlurChain 1.29, MaskedBlur 1.50
  - 1080p (1920×1080): Render 1.23, Crossfade 2.33, BlurChain 2.77, MaskedBlur 2.86
  - 4K (3840×2160): Render 5.00, Crossfade 8.74, BlurChain 8.45, MaskedBlur 10.59
  - 8K (7680×4320): Render 13.96, Crossfade 24.48, BlurChain 34.26, MaskedBlur 45.30

## Changes

### YYYY-MM-DD — <short change title>
- Change:
- Files touched:
- Why:
- Expected impact (GPU time/bandwidth/CPU):
- Evidence:
  - Before: <avg ms/frame>
  - After: <avg ms/frame>
  - Delta: <ms and %>
- Notes / risks:

### YYYY-MM-DD — <short change title>
- Change:
- Files touched:
- Why:
- Evidence:
  - Before:
  - After:
- Notes:
