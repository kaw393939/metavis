# 2025 Companion Research: Advanced Rendering & PBR

**Date:** 2025-12-20
**Scope:** Metal 3, PBR, Volumetrics, Mesh Shaders
**Status:** COMPLETE

## 1. Executive Summary
This document serves as the 2025 "state of the art" companion to the legacy rendering specs. It focuses on leveraging Apple Silicon's Unified Memory Architecture (UMA) and Metal 3 features (Mesh Shaders, Hardware Ray Tracing) to modernize the rendering pipeline.

## 2. PBR & Material Workflows
**Legacy:** Disney Principled BRDF (2012/2015 era).
**2025 State of the Art:**
*   **MaterialX & Bindless Rendering:** Moving towards massive material libraries. Metal 3's "Bindless" rendering allows accessing thousands of textures from a single shader via Argument Buffers/Heaps, removing draw call overhead.
*   **Stochastic Transparency:** Instead of alpha blending (sorting issues), use stochastic alpha testing + temporal accumulation/denoising.
*   **Neural Materials:** Emerging trend of encoding complex BRDFs (like fabric/skin) into small MLP networks evaluated in the fragment shader.

## 3. Geometry & Volumetrics
**Legacy:** Raymarching on quads, standard vertex/fragment pipeline.
**2025 State of the Art:**
*   **Mesh Shaders:** Replace the Vertex Shader -> Rasterizer pipeline for complex geometry (like procedural terrain or millions of particles). This allows culling whole "meshlets" before rasterization.
*   **Volumetric Clouds via 3D Gaussian Splatting (V^3):** 2024/2025 papers (SIGGRAPH) show moving from raymarching to projecting "2D Dynamic Gaussians" for mobile-friendly volumetric video/clouds. This is a massive leap in performance.
*   **Hybrid Ray Tracing:** Use hardware acceleration for specific effects (Shadows, Reflections, AO) while keeping the main pass rasterized. Metal 3 provides `Intersector` APIs for this mixed mode.

## 4. Implementation Recommendations
1.  **Adopt Mesh Shaders** for all procedural geometry (Terrain, Particles).
2.  **Investigate Gaussian Splatting** as a replacement for the legacy raymarched Nebula system.
3.  **Upgrade PBR** to use Bindless heaps (Argument Buffers) for infinite texture sets.
