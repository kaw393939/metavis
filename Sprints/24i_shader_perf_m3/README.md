# Sprint 24i — Shader Performance Pass (M3+)

## Goal
Turn the shader registry into a concrete, repeatable performance plan for Apple M3+ (bandwidth, occupancy, and PSO behavior), without changing user-facing behavior.

## Scope
This sprint is explicitly about *performance*, not new features.

- No UX changes.
- No effect semantic changes.
- Validate via existing tests and deterministic render checks where applicable.

## Coverage
- Owned shader files (primary):
  - Sources/MetaVisGraphics/Resources/Blur.metal
  - Sources/MetaVisGraphics/Resources/MaskedBlur.metal
  - Sources/MetaVisGraphics/Resources/Temporal.metal
  - Sources/MetaVisGraphics/Resources/Noise.metal
- Registry grounding:
  - shader_archtecture/REGISTRY.md
  - shader_archtecture/COVERAGE_MATRIX_24H_24O.md

## Workstreams
### 1) Profiling methodology (repeatable)
- Representative graphs to profile:
  - SMPTE → output (baseline)
  - SMPTE → blur_h → blur_v (bandwidth heavy)
  - 2-clip transition (compositor kernels)
  - masked blur (mask path)
- Tools:
  - Xcode GPU Frame Capture
  - Metal System Trace

### 2) PSO specialization strategy
- Identify “hot kernels” and their parameter permutations.
- Decide where function constants provide meaningful wins without exploding PSO count.
- Ensure PSO cache hit rate in steady state.

### 3) Texture format + lifetime policy
- Confirm per-stage formats and when non-float formats are permitted.
- Confirm pooling/lifetime doesn’t violate hazards.

### 4) Kernel-level optimizations (surgical)
- **MaskedBlur.metal**: Replace $O(R^2)$ loop with Mipmap Interpolation or `MPSImageGaussianBlur`. See `shader_research/Research_MaskedBlur.md`.
- **Noise.metal**: Switch from ALU-heavy FBM to 3D Noise Textures. See `shader_research/Research_Noise.md`.
- **Temporal.metal**: Implement Velocity Buffer Reprojection to fix ghosting. See `shader_research/Research_Temporal.md`.
- **General**: Use `exec_scope_group_inclusive_add` (SIMD) for reductions instead of `atomic_fetch_add` where applicable.

## Acceptance criteria
- Notes are checked in (no binary captures required) describing what was measured and why.
- **Numeric gate (M3+)**: On Apple M3+ hardware, demonstrate **\u226515% reduction** in average ms/frame on **at least one** representative graph listed in `MEASUREMENT.md`, compared to the baseline recorded in `FINDINGS.md`.
  - Measurement source of truth: `Tests/MetaVisSimulationTests/Perf/RenderPerfTests.swift` (run with `METAVIS_PERF_LOG=1`).
  - Evidence required in `FINDINGS.md`: device model, macOS version, command/env used, baseline vs after numbers.
- No regressions in existing tests.

## How to run
See MEASUREMENT.md for the runbook.

## Task list
See TASKS.md for per-shader tasks derived from `shader_research/`.

## Related sprints (do not lose track)
- 24k: ACES 1.3 + tone scale correctness (color science)
- 24l: Post stack fusion (pass-count/bandwidth reduction)
- 24n: QC + waveform reductions (atomics + scope kernel best practices)

## Keeping this up to date
- Log each tuning change (with before/after numbers) in FINDINGS.md.
- When a decision becomes stable (e.g., format/lifetime policy), fold it back into this README.
