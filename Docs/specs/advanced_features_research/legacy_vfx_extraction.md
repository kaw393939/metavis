# Legacy VFX Extraction Report

**Date:** 2025-12-20
**Scope:** `metavis1` (Shaders)
**Status:** COMPLETE

## 1. Executive Summary
This report details the specific visual effects shaders located in `metavis1`. These provide the "Cinematic Polish" layer for the engine.

## 2. Feature Deep Dive

### A. Volumetric Light (God Rays)
**Source:** `metavis1/.../Shaders/Effects/Volumetric.metal`
**Technique:** Screen-Space Raymarching (2D Approximation)
**Details:**
*   Marches rays from pixel towards screen-space light position.
*   **Occlusion:** Reads Depth Buffer to block rays behind objects.
*   **Optimization:** Uses "Interleaved Gradient Noise" to dither start positions and hide banding.

### B. Cinematic Lens System
**Source:** `metavis1/.../Shaders/Effects/Lens.metal`
**Technique:** Brown-Conrady Distortion + Spectral Chromatic Aberration
**Details:**
*   **Distortion:** `k1` and `k2` parameters for Barrel/Pincushion.
*   **Coupled CA:** Chromatic aberration is calculated *after* distortion, physically correcting for the lens shape.
*   **Spectral Separation:** R/G/B channels are sampled at different UV offsets.

### C. Physically Based Bloom
**Source:** `metavis1/.../Shaders/Effects/Bloom.metal`
**Technique:** Dual Filter (Jimenez) + Karis Average
**Details:**
*   **Firefly Reduction:** Uses "Karis Average" (1 / 1+Luma) during downsampling to prevent flickering from bright pixels.
*   **Upsampling:** Uses **12-tap Golden Angle Spiral** blur instead of standard Tent filter. This is a high-end choice that avoids "square" looking bloom highlights.
*   **Composite:** Strictly additive blend to preserve energy.

## 3. Integration Plan

These shaders belong in `MetaVisGraphics/Shaders/Effects/`.

1.  **Bloom:** Critical for HDR workflows. Port first.
2.  **Lens:** Adds the "Film Look". Port second.
3.  **Volumetric:** Good for specific shots, but less critical than Bloom.
