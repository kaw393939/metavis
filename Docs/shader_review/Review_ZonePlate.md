# Shader Review: ZonePlate.metal

**File**: `Sources/MetaVisGraphics/Resources/ZonePlate.metal`
**Target**: Apple Silicon M3 (Metal 3)

## Status: Aliasing Test
*   **Analysis**:
    *   Generates Sinusoidal Zone Plate.
    *   **Sampling**: Uses pixel center (`gid + 0.5`). This is correct for a digital test chart.
    *   **ALU**: Uses `sin/cos` heavily per pixel.
*   **M3 Optimization**:
    *   **None**: The purpose is to be mathematically precise, not fast. M3 handles it easily.

## Action Plan
- [ ] **No Changes needed**.
