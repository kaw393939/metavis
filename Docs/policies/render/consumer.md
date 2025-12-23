# Render Policy: consumer

Intent: prioritize performance and resilience.

Defaults:
- Edge compatibility: auto-resize inputs when dimensions mismatch.
- Auto-resize kernel: bilinear (`resize_bilinear_rgba16f`).

Notes:
- This tier is designed to keep graphs rendering even if an effect chain has resolution mismatches.
