# Shader Review: Watermark.metal

**File**: `Sources/MetaVisGraphics/Resources/Watermark.metal`
**Target**: Apple Silicon M3 (Metal 3)

## Status: Simple Overlay
*   **Analysis**:
    *   Diagonal stripes.
*   **M3 Optimization**:
    *   **Branching**: `if (stripe)` can be replaced with `mix(color, stripeColor, mask)`.
    *   **ALU**: Use `step` and `mod` for mask generation.

## Action Plan
- [ ] **Optimize**: Refactor to branchless mix.
