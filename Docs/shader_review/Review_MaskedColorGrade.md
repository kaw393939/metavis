# Shader Review: MaskedColorGrade.metal

**File**: `Sources/MetaVisGraphics/Resources/MaskedColorGrade.metal`
**Target**: Apple Silicon M3 (Metal 3)

## Status: HSL Selection
*   **Analysis**:
    *   Uses HSL to select specific colors for grading (Secondary Correction).
    *   **Critique**: `rgb2hsl` is branch-heavy and slow.
*   **M3 Optimization**:
    *   **HCV**: Use the **Hue-Chroma-Value** model. It's fully branchless and maps better to GPU architectures.
    *   **SIMD**: Branchless math ensures 100% vector utilization.

## Action Plan
- [ ] **Refactor**: Replace HSL math with HCV (Hue-Chroma-Value).
