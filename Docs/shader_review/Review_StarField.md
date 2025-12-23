# Shader Review: StarField.metal

**File**: `Sources/MetaVisGraphics/Resources/StarField.metal`
**Target**: Apple Silicon M3 (Metal 3)

## Status: Tiled Generator
*   **Analysis**:
    *   Spatial hashing for infinite stars.
    *   Checks neighbor cells.
*   **M3 Optimization**:
    *   **Registers**: Neighbor checking (3x3) increases register pressure. Ensure loops are tight.
    *   **ALU**: Hash function should be fast (PCG or similar).

## Action Plan
- [ ] **Review**: Check hash function performance in Instruments. Otherwise good.
