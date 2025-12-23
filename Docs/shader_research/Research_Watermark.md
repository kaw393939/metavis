# Research: Watermark.metal

**Target**: Apple Silicon M3 (Metal 3)
**Goal**: Overlay

## 1. Math
**Function**: Diagonal stripes. $Mod(x+y, stride)$.

## 2. Technique: Branchless
**Optimization**:
*   `float stripe = step(width, mod(x+y, stride));`
*   `color = mix(color, color * 0.5, stripe * opacity);`
*   Avoid `if (stripe)` branching.

## 3. M3 Architecture
**ALU**:
*   `fmod` is fast.
*   Keep it simple.

## Implementation Recommendation
Refactor to **Branchless mix()**.
