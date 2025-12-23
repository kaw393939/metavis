# Research: StarField.metal

**Target**: Apple Silicon M3 (Metal 3)
**Goal**: Infinite Starfield

## 1. Math
**Technique**: Divide space into grid cells. Each cell has N stars.
**Hash**: Determine star position based on `hash(cell_id)`.
**Distance**: Calculate distance to stars in neighbor cells (3x3 grid).

## 2. Technique: Spatial hashing
**Optimization**:
*   Use a deterministic hash (like `pcg3d`) that is fast on ALU.
*   Avoid storing stars in memory.

## 3. M3 Architecture
**Registers**:
*   Checking 9 neighbor cells * N stars can use many registers.
*   Keep N small (e.g., 1-2 stars per cell) and increase frequency (smaller cells) to maintain density. This allows unrolling the loop.

## Implementation Recommendation
Use **Spatial Hashing** with 3x3 neighbor search. Optimize hash function for M3 ALU.
