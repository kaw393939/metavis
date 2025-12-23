# Research: ToneMapping.metal

**Target**: Apple Silicon M3 (Metal 3)
**Goal**: ACES 1.3 Output Match

## 1. Math
**Current**: Reinhard ($x/(x+1)$).
**Problem**: Desaturates highlights; incorrect contrast roll-off.
**Solution**: **ACES SSTS (Single Stage Tone Scale)**.
*   Segmented Spline curve defined in ACES spec.
*   Preserves saturation in highlights (using RRT sweeteners).

## 2. Technique: Analytical Spline
**Optimization**:
*   Avoid 3D LUTs for Tone Mapping if possible.
*   Use analytical spline functions (5 segments).
*   High ALU usage, 0 Bandwidth usage. Ideal for M3.

## Implementation Recommendation
Implement **ACES 1.3 SSTS** curve analytically.
