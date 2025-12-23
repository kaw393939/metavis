# Shader Review: Procedural.metal

**File**: `Sources/MetaVisGraphics/Resources/Procedural.metal`
**Target**: Apple Silicon M3 (Metal 3)

## Status: SDF Library
*   **Analysis**:
    *   Contains Signed Distance Functions for shapes.
*   **M3 Optimization**:
    *   **Anti-Aliasing**: Ensure `smoothstep` widths are calculated using `fwidth()` (derivatives). M3 handles derivatives efficiently in 2x2 blocks.
    *   **Branching**: Avoid `if` inside SDFs. Use `mix` and `step`.

## Action Plan
- [ ] **Update**: Verify AA logic uses `fwidth`.
