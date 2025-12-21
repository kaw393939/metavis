# 2025 Companion Research: Simulation & Procedural Generation

**Date:** 2025-12-20
**Scope:** Fluid, Noise, GPU Graphs
**Status:** COMPLETE

## 1. Executive Summary
This document explores the 2025 landscape for real-time simulation on Apple platforms, comparing legacy grid-based methods with modern Compute techniques and Graph execution.

## 2. Fluid Simulation: Grid vs. Curl Noise
**Legacy:** Curl Noise (Procedural).
**2025 State of the Art:**
*   **Curl Noise** remains the king of *visual* performance for "fake" fluids (smoke, ambient movement) because it is incompressible by definition and stateless.
*   **Hybrid Grid/Particle (MPM/PIC/FLIP):** For "hero" fluids (pouring water), Metal Compute enables high-res grid methods (32-bit floats) that run entirely on GPU.
*   **Recommendation:** Stick to **Curl Noise** for background/ambient/UI effects (stateless, instant), but if "Simulation Workbench" needs physical water, implement a **Compute-based FLIP solver**.

## 3. GPU Graph Execution
**Legacy:** Custom "Graph Interpreter" Shader (slow, interpreted).
**2025 State of the Art:**
*   **MPSGraph:** Apple's graph compiler. While mainly for ML tensors, it can be abused for general compute. However, it's opaque.
*   **Metal Performance Shaders (MPS):** No generic noise filters yet.
*   **Computed Kernels (The "Uber-Kernel" approach):** The legacy approach of "interpreting" a graph on GPU is slow (divergency).
*   **JIT Compilation (Metal 3):** The pro move in 2025 is to **compile** the node graph into a new Metal Library at runtime (using `MTLDynamicLibrary` or offline compilation). *Don't interpret the graph; compile the graph.*

## 4. Procedural Noise
**Legacy:** Standard Perlin/Simplex.
**2025 State of the Art:**
*   **Stochastic Sampling:** Use blue noise correlations for better dither.
*   **Pre-baking:** 3D Volume textures for noise are standard.
*   **Hash-free Noise:** Techniques that avoid the expensive hash lookup by creating tiling textures.

## 5. Implementation Recommendations
1.  **Refactor Node Graph:** Move from "Interpreter" to "Transpiler". Convert user node graphs into MSL strings -> Compile to `MTLLibrary` (asynchronously) -> Run native shader.
2.  **Keep Curl Noise:** It is still the most efficient way to get "fluid-like" motion without solving Navier-Stokes.
