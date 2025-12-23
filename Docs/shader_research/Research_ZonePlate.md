# Research: ZonePlate.metal

**Target**: Apple Silicon M3 (Metal 3)
**Goal**: Precision Test Signal

## 1. Math
**Function**: $Sin(k \cdot r^2)$.
**Purpose**: Sweeps spatial frequencies to test aliasing and Moiré handling.

## 2. Technique: High Precision
**Requirement**:
*   We *start* with `float` precision.
*   Calculate `sin` precisely.
*   **Do Not Optimize**: This is a test chart. It *should* exhibit aliasing if the pipeline is bad (that is its purpose).

## 3. M3 Architecture
**Trigonometry**:
*   M3 `sin/cos` units are high throughput.
*   Generating this procedurally at 8K 120fps is trivial for M3.

## Implementation Recommendation
**Keep As Is**. Ensure `gid + 0.5` center checking is preserved for sampling accuracy.
