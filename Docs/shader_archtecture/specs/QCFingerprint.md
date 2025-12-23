# QCFingerprint.metal

## Purpose
QC compute shaders for fingerprinting and color statistics.

## Kernels
- `qc_fingerprint_accumulate_bgra8`
  - `src` `texture(0)` (sample, `half`)
  - `out` `buffer(0)` (`QCFingerprintAccum`, uses atomics)
  - Dispatch: typically 64x36 grid

- `qc_fingerprint_finalize_16`
  - `accum` `buffer(0)` → `out` `buffer(1)`
  - Dispatch: 1 thread

- `qc_colorstats_accumulate_bgra8`
  - `src` `texture(0)`
  - `accum` `buffer(0)`
  - `histogram` `buffer(1)` (256 bins)
  - `targetW` `buffer(2)`, `targetH` `buffer(3)`

## Call sites
- `Sources/MetaVisQC/MetalQCFingerprint.swift`
- `Sources/MetaVisQC/MetalQCColorStats.swift`

## Performance notes (M3+)
- Atomics dominate; keep the working resolution small (downsample) and prefer relaxed atomics (already used).
