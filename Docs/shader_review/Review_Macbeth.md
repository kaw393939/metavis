# Shader Review: Macbeth.metal

**File**: `Sources/MetaVisGraphics/Resources/Macbeth.metal`
**Target**: Apple Silicon M3 (Metal 3)

## Status: Reference Chart
*   **Analysis**:
    *   Static generator for ColorChecker.
    *   **Accuracy**: Uses `constant float3` arrays. Values appear to be ACEScg linear.
*   **M3 Optimization**:
    *   **Constant Memory**: Using `constant` address space is optimal for L1 caching.
    *   **Branching**: Simple UV grid logic is negligible cost.

## Action Plan
- [ ] **Verify**: Double check spectral values against BabelColor 2025 constants.
