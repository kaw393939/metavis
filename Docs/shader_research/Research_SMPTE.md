# Research: SMPTE.metal

**Target**: Apple Silicon M3 (Metal 3)
**Goal**: Broadcast Compliance

## 1. Math
**Standard**: SMPTE RP 219-2002 (HD Bars).
**Levels**:
*   75% Bars vs 100% Bars.
*   PLUGE (Picture Line-Up Generation Equipment) signals (-4%, 0%, +4% black).

## 2. Technique: Branchless Generation
**Current**: `if (uv.x < a) ... else if (uv.x < b)...`
**Optimization**:
*   Create a 1D Texture (or 1D array) of colors.
*   `int index = int(uv.x * NumBars);`
*   `color = Bars[index];`
**Benefit**: Removes branching divergence.

## 3. M3 Architecture
**Constant Memory**:
*   Store the Bar Colors in `constant` address space.

## Implementation Recommendation
Verify 75% levels are physically accurate in Linear space (approx 0.75^2.2?), or explicitly Rec.709 encoded.
