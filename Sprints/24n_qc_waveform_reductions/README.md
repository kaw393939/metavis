# Sprint 24n — QC + Scope reductions (atomics)

## Goal
Eliminate pathological global atomic contention in QC fingerprinting and ensure scope kernels follow best practices.

## Coverage
- Matrix of all owned files: [shader_archtecture/COVERAGE_MATRIX_24H_24O.md](shader_archtecture/COVERAGE_MATRIX_24H_24O.md)

### Owned files (primary)
- QC kernels:
	- [Sources/MetaVisQC/Resources/QCFingerprint.metal](Sources/MetaVisQC/Resources/QCFingerprint.metal)

### Shared file responsibility
- Scope/waveform kernels live alongside other color code in:
	- [Sources/MetaVisGraphics/Resources/ColorSpace.metal](Sources/MetaVisGraphics/Resources/ColorSpace.metal)
24n owns the waveform/scope portions (threadgroup sizing, access patterns, atomic reduction strategy), while 24k owns color-science correctness.

## Targets
## Targets
- `QCFingerprint.metal`: Implement 3-stage reduction (Simd `simd_sum` -> Threadgroup Shared Memory -> Global Atomic) to eliminate contention. See `shader_research/Research_QCFingerprint.md` (implied).
- `ColorSpace.metal`: Optimize waveform accumulation using similar threadgroup binning strategies.
- **Reference**: See `shader_research/Research_ColorSpace.md` for branchless logic that should accompany these kernels.

## Acceptance criteria
- QC fingerprint path reduces global atomic ops per frame substantially.
- Verified correctness vs prior implementation on a small golden set.
