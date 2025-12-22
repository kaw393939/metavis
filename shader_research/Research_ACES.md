# Research: ACES.metal

**Target**: Apple Silicon M3 (Metal 3)
**Goal**: Studio Grade ACES 1.3 Compliance

## 1. Math & Physics
**Current Status**: Implicit/Fitted RRT (Stephen Hill fit).
**Problem**: Lacks ACES 1.3 Gamut Compression and proper ODT sweeteners (Red Modifier, Glow).
**Solution (2025)**:
*   **Analytical RRT & ODT**: Use the segmented spline math from ACES 1.3 spec, not fitted curves.
*   **Gamut Compression**: Implement the Reference Gamut Compression (RGC) to fix blue-light artifacts.
    $$ v_{compressed} = \frac{v}{1 + v} $$ (distance based).

## 2. Technique: Branchless Logic
**Technique**: Replace `if (linear < threshold)` checks with intrinsic select.
**Code Strategy**:
```metal
// M3 Optimized
inline half3 branchless_ACEScct(half3 lin) {
    bool3 isToe = lin <= ACEScct_X_BRK;
    return select((log2(lin) + 9.72h) / 17.52h, (ACEScct_A * lin + ACEScct_B), isToe);
}
```

## 3. M3 Architecture
**SIMD Scoped Ops**:
*   The M3 shader core handles `half3` vectors natively in its 128-bit SIMD ALUs.
**Instruction Parallelism**:
*   Analytical splines allow the compiler to interleave Arithmetic ops with Logic ops better than LUT fetches (memory bound).

## Implementation Recommendation
Rewrite `ACES.metal` to implement the full ACES 1.3 Analytical chain.
