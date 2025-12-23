# Shader Review: LightLeak.metal

**File**: `Sources/MetaVisGraphics/Resources/LightLeak.metal`
**Target**: Apple Silicon M3 (Metal 3)

## Status: Procedural Overlay
*   **Analysis**:
    *   Generates additive shapes/gradients.
*   **M3 Optimization**:
    *   **Resolution**: Light leaks are low-frequency. Generating them at 8K is wasteful via ALU.
    *   **Strategy**: Render the leak to a **512x512** texture, then upscale-composite it.
    *   **Gain**: 200x reduction in fragment shader invocations.

## Action Plan
- [ ] **Low-Res**: Change engine to render leaks to a small intermediate buffer.
