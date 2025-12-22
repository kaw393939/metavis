# Research: Compositor.metal

**Target**: Apple Silicon M3 (Metal 3)
**Goal**: Zero Bandwidth Blending

## 1. Math & Physics
**Math**: Porter-Duff Compositing (Source Over).
$$ C_{out} = C_{src} \cdot \alpha_{src} + C_{dst} \cdot (1 - \alpha_{src}) $$

## 2. Technique: Raster Programmable Blending
**Current**: Compute Shader reading Texture A and Texture B, writing Texture C.
**Bottleneck**: DRAM Bandwidth (~100GB/sec consumed just for simple blending).

## 3. M3 Architecture (Tile Memory)
**Feature**: **Programmable Blending** (`[[color(0)]]`).
*   Metal allows reading the *current* framebuffer value in a Fragment Shader.
*   This read comes from **On-Chip Tile Memory** (SRAM), not VRAM.
*   **Result**: Input Read = Texture A. Destination Read = Free. Write = Free (until tile flush).
*   **Performance**: 2x-4x speedup for multi-layer compositing.

## Implementation Recommendation
Move from Compute Kernel to **Render Pipeline** with Programmable Blending.
