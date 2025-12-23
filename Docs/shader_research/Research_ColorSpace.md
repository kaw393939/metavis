# Research: ColorSpace.metal

**Target**: Apple Silicon M3 (Metal 3)
**Goal**: Branchless Transfer Functions

## 1. Math & Physics
**Math**: Transfer Functions (EOTF/OETF) like sRGB, Rec.709, PQ.
**Problem**: Defined piecewise. E.g., sRGB has a linear toe and a power curve.
$$ y = \begin{cases} 12.92x & x \le 0.04045 \\ 1.055x^{1/2.4} - 0.055 & x > 0.04045 \end{cases} $$

## 2. Technique: Minimax Polynomials
**Optimization**: Piecewise branches cause warp divergence.
**Solution**: Fit a single polynomial (degree 5 or 6) that approximates the entire curve 0..1 with error $< 10^{-5}$.
**Alternative**: Keep piecewise but use `select()` (branchless selection).

## 3. M3 Architecture
**SIMD**:
*   Branchless execution ensures all 32 threads in a SIMD group retire continuously.
*   Use `fast::pow` (approximate) where strict 10-bit broadcast compliance isn't critical (preview).

## Implementation Recommendation
Refactor all transfer functions (`sRGB_to_Linear`, etc.) to use **Branchless `select()`** logic.
