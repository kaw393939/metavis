# 2025 Companion Research: Text & Vector Graphics

**Date:** 2025-12-20
**Scope:** MSDF, Mesh Shaders, Metal 3
**Status:** COMPLETE

## 1. Executive Summary
Text rendering has matured significantly. While SDF is standard, Multi-Channel SDF (MSDF) is the 2025 standard for sharp corners. Mesh Shaders offer a new path for high-fidelity vector rendering.

## 2. Text Rendering: SDF vs. MSDF vs. Mesh
**Legacy:** Single-Channel SDF.
**2025 State of the Art:**
*   **MSDF (Multi-Channel Signed Distance Field):** Encodes shape in RGB channels to preserve sharp corners. This is the industry standard for 2D UI and "infinite zoom" text.
*   **Mesh Shaders for Text:** For massive 3D text (e.g., "Star Wars" intro style), generating geometry in a Mesh Shader is superior to drawing quads. It allows dynamic tessellation for curves.
*   **Recommendation:** Upgrade the legacy SDF generator to **MSDF** (using the Felzenszwalb algorithm per channel).

## 3. Vector Graphics on Metal
**Legacy:** Rasterization.
**2025 State of the Art:**
*   **GPU-Driven Path Rendering:** Using Compute to bin/sort paths, then rasterizing.
*   **Sparse Strips:** A new technique (Rust Week 2025) for efficient vector paths.
*   **Mesh Shaders:** Tesselating SVG paths directly on GPU.

## 4. Implementation Recommendations
1.  **Upgrade SDF Generator:** Implement **MSDF** generation (requires 3 passes of EDT, or a specific MSDF algorithm).
2.  **Use 16-bit Float Textures:** `rgba16Float` allows for higher precision distance fields, reducing "wobble" at extreme zooms.
