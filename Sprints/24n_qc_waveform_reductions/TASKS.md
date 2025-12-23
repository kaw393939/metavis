# Sprint 24n — TASKS

## Goal
Eliminate pathological atomic contention in QC fingerprinting and reduce scope/waveform cost.

## 1) QC fingerprint reductions
- [ ] Implement 3-stage reduction in `Sources/MetaVisQC/Resources/QCFingerprint.metal`:
  - SIMD lane sum (`simd_sum`)
  - threadgroup reduction
  - 1 global atomic add per threadgroup
- [ ] Add a small golden set to validate correctness vs prior implementation.
- [ ] Measure before/after with existing perf harness (record in metrics output).

## 2) Scope / waveform reductions
- [ ] Identify waveform/scope kernels within `Sources/MetaVisGraphics/Resources/ColorSpace.metal`.
- [ ] Apply threadgroup binning/reduction strategy to minimize global atomics.
- [ ] Keep color-science behavior unchanged (24k owns correctness; 24n owns performance).

## Acceptance
- [ ] Atomic ops per frame drop substantially in QC.
- [ ] Output matches prior implementation on goldens.
- [ ] Perf improves measurably at 1080p/4K.
