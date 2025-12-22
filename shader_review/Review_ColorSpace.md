# Shader Review: ColorSpace.metal

**File**: `Sources/MetaVisGraphics/Resources/ColorSpace.metal`  
**Reviewer**: Antigravity  
**Target Hardware**: Apple Silicon M3 (Metal 3)  
**Context**: Core Color Management & Analysis

## Overview
This file defines the foundational color math for the pipeline, including IDTs (Input Device Transforms), ODTs (Output Device Transforms), and transfer functions (sRGB, PQ, HLG). It also includes the waveform scope implementation.

## ACES Compliance & Correctness
1.  **Matrices**: Use standard CAT02 derived matrices for Rec.709/Rec.2020 <-> ACEScg.
    *   *Status*: **Passable**. Values match standard approximations, but should be cross-referenced with `ampas/aces-core` CTL for 6-decimal precision.
2.  **Transfer Functions**:
    *   `sRGB_to_Linear` / `Linear_to_sRGB`: Standard piecewise functions.
    *   `Linear_to_PQ` / `Linear_to_HLG`: Look correct for standard definitions.

## Apple Silicon M3 Optimizations

### 1. Branch Divergence in Transfer Functions
*   **Current**: Uses `if/else` inside `for` loops.
    ```cpp
    for (int i = 0; i < 3; i++) {
        if (srgb[i] <= 0.04045) { ... } else { ... }
    }
    ```
*   **Problem**: On SIMD architectures (M3 GPU), threads in a SIMD-group (wavefront) must execute in lock-step. If pixels diverge (one color channel is below threshold, another above), the hardware serializes both paths, masking off inactive threads. This halves throughput for these pixels.
*   **Optimization**: Use **Branchless Selection**.
    ```cpp
    // Example Optimization
    float3 is_linear = step(srgb, 0.04045); // 1.0 if <= threshold
    float3 lin_part = srgb / 12.92;
    float3 exp_part = pow((srgb + 0.055) / 1.055, 2.4);
    return mix(exp_part, lin_part, is_linear);
    ```
    M3 ALUs handle `mix` (linear interpolation) extremely fast.

### 2. Atomic Contention in Waveforms
*   **Current**: `atomic_fetch_add_explicit` on global device memory for *every pixel*.
    ```cpp
    atomic_fetch_add_explicit(&grid[index], 1, memory_order_relaxed);
    ```
*   **Problem**: For a 4K frame (8M pixels), this causes massive cache trashing and contention on the `grid` buffer in global memory. This is the primary bottleneck for `scope_waveform_accumulate`.
*   **Optimization (M3)**:
    1.  **SIMD-Group Reduction**: Use `simd_sum` to aggregate counts within a thread execution width (32 threads) before writing to memory.
    2.  **Threadgroup Memory**: Use `threadgroup` local memory to bin pixels for a 16x16 or 32x32 tile, then flush the tile histogram to global memory once per tile.
    *   *Impact*: Could speed up scope generation by 10x-50x.

### 3. Half Precision (Float16)
*   **Current**: Uses `float` everywhere.
*   **Opportunity**: M3 has double-rate FP16 performance.
*   **Recommendation**:
    *   For `sRGB` and `Rec.709` (Standard Dynamic Range), `half` precision is sufficient and 2x faster.
    *   For `PQ` / `ACES` (HDR), stay in `float` for linear light to avoid banding in shadows (denormals), or carefully verify `half` usage.

## Usage in Simulation
*   **Pipeline**: Used in `MetalSimulationEngine.swift` for `idt_rec709_to_acescg`, `odt_acescg_to_rec709`, and scope generation (`scope_waveform_accumulate`).
*   **Criticality**: High. This code runs on every pixel of raw footage.

## Action Plan
- [ ] Refactor transform functions to be branchless.
- [ ] Rewrite `scope_waveform_accumulate` to use `threadgroup` memory and SIMD reductions.
- [ ] Investigate `half` variants for SDR pipelines.
