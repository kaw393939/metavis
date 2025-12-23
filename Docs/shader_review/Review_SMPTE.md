# Shader Review: SMPTE.metal

**File**: `Sources/MetaVisGraphics/Resources/SMPTE.metal`
**Target**: Apple Silicon M3 (Metal 3)

## Status: Broadcast Generator
*   **Analysis**:
    *   Generates SMPTE RP 219 bars.
*   **M3 Optimization**:
    *   **No issues**: Simple procedural logic.
    *   **Precision**: Ensure PLUGE signals (-4%, +4%) are accurate in the pipeline's working color space (Linear vs Rec.709).

## Action Plan
- [ ] **No Changes needed**.
