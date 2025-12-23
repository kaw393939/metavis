# Shader Review: Test Generators (Batch 3 Continued)

**Files**:
- `Macbeth.metal`
- `SMPTE.metal`
- `ZonePlate.metal`
- `ClearColor.metal`

**Target**: Accuracy & Reference Implementations.

## 1. Reference Charts (`Macbeth`, `SMPTE`)
**Status**: Solid static generators.
*   **Accuracy Check**: Colors are defined as `constant float3`. Values appear to be valid ACEScg linear reflectances/emitters.
*   **M3 Implementation**:
    *   Hardcoded constants are efficient.
    *   No branching divergence (simple UV partitioning).
    *   **Recommendation**: Keep as is. Ensure documentation specifies that output is *Linear ACEScg* and requires ODT for viewing.

## 2. Signal Analysis (`ZonePlate`)
**Status**: Standard sinusoidal zone plate.
*   **Purpose**: Tests aliasing and frequency response.
*   **Critique**: Uses pixel center sampling `(gid + 0.5)`.
    *   This is correct for a *digital check chart* (we want to see the aliasing).
    *   **M3**: Uses `sin/cos`, heavy ALU but negligible for a test chart.

## Summary Action Points
- [ ] **Generators**: No code changes needed. Verify ACEScg values against BabelColor database one last time during implementation.
