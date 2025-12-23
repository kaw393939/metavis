# Shader Review: Halation.metal

**File**: `Sources/MetaVisGraphics/Resources/Halation.metal`
**Target**: Apple Silicon M3 (Metal 3)

## Status: Physically Based Loop
*   **Analysis**:
    *   Loops to create a red-tinted scatter.
    *   **Redundant Work**: This is effectively a small-radius bloom on the red channel.
*   **M3 Optimization**:
    *   **Fuse**: Instead of a separate pass, sample the existing **Bloom Mip Level 1** or **2**.
    *   **Tint**: Apply the red tint during the final composition.
    *   **Gain**: Saves an entire read/write pass of the 4K buffer (freq 60Hz -> 500MB/s savings).

## Action Plan
- [ ] **Merge**: Integrate Halation logic into the final uber-shader compositor by utilizing Bloom resources.
- [ ] **Optimize**: Ensure `uniforms.radialFalloff` creates zero-cost branching (uniform condition).
