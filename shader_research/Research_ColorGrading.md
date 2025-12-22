# Research: ColorGrading.metal

**Target**: Apple Silicon M3 (Metal 3)
**Goal**: High Precision Grading

## 1. Math & Physics
**Math**: Trilinear Interpolation of a 3D Lattice (LUT).
**Math (Log Shaper)**: LUTs expect Logarithmic input to distribute samples perceptually efficiently. $Pos = Log(LinearIn)$.

## 2. Technique: Tetrahedral Interpolation
**Quality**: Standard hardware uses Trilinear. For high-end "Studio" grading, **Tetrahedral** interpolation (splitting the cube into tetrahedra) avoids color banding on diagonals.
**Performance**: Tetrahedral requires manual ALU math (software lerp).

## 3. M3 Architecture
**Texture Units**: M3 has massive texture filtering throughput.
*   **Trilinear**: Free (1 cycle).
*   **Tetrahedral**: ~15 ALU cycles.
**Decision**: For real-time 8K preview, Trilinear is acceptable. For Final Export, Tetrahedral is preferred.

## Implementation Recommendation
*   Default: Use Hardware Trilinear 3D Sample.
*   Optimization: Precompute a **1D Shaper LUT** instead of doing `Log2`/`Exp2` math in the shader.
