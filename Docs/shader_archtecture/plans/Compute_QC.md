# Plan: Compute_QC (QC fingerprint reduction)

Source research: `shader_research/Research_Compute_QC.md`

## Owners / entry points

- Shader: `Sources/MetaVisQC/Resources/QCFingerprint.metal`
- Kernels:
  - `qc_fingerprint_accumulate_bgra8` (currently the hot path)
  - `qc_fingerprint_finalize_16`
  - `qc_colorstats_accumulate_bgra8`

## Problem summary (from research)

- Global atomic accumulation per pixel causes extreme contention.

## Target architecture fit

- Use hierarchical reduction:
  - SIMD subgroup reduction (`simd_sum`) → threadgroup memory reduction → single global atomic per TG.

## RenderGraph integration

- Tier: Full (reduction output is small)
- Fusion group: Standalone
- Perception inputs: none
- Required graph features: Hierarchical reduction; avoid global atomics.
- Reference: `shader_archtecture/RENDER_GRAPH_INTEGRATION.md` (Compute_QC)

## Implementation plan

1. **Rewrite accumulate kernel**
   - Replace per-thread global atomics with a 3-stage reduction.
2. **Threadgroup shape**
   - Choose TG dimensions to maximize occupancy while minimizing shared memory.
3. **Finalize pass**
   - Keep finalize as-is unless it becomes a bottleneck.
4. **Color stats**
   - Apply the same reduction strategy for `qc_colorstats_accumulate_bgra8`.

## Validation

- Correctness: fingerprint bytes match baseline.
- Performance: atomics drop by ~TG-size factor; kernel time reduces meaningfully at 4K/8K.

## Sprint mapping

- Primary: `Sprints/24n_qc_waveform_reductions`
