# Legacy Core Math & Color Report

**Date:** 2025-12-20
**Scope:** `metavis1` (Shaders/Core)
**Status:** COMPLETE

## 1. Executive Summary
This report details the mathematical foundations found in `metavis1`. These libraries provided the "Hollywood Grade" image quality.

## 2. Feature Deep Dive

### A. ACES Color Engine
**Source:** `metavis1/.../Core/ACES.metal`
**Algorithm:** ACES 1.3 RRT + ODTs
**Key Capabilities:**
*   **Full Pipeline:** Implements the Reference Rendering Transform (RRT) and Output Device Transforms (ODT).
*   **Target Support:** 
    *   `Rec.709` (SDR Web/TV)
    *   `P3-D65` (Apple Devices)
    *   `Rec.2020 PQ` (HDR10 / Dolby Vision)
*   **Sweeteners:** Includes "Saturation Sweetener" to fix color skewing in bright highlights (a common issue in simple tone mappers).
*   **Grading Support:** Implements `ACEScct` (Logarithmic) encoding/decoding, which is used for Color Grading interaction.

### B. Noise Library
**Source:** `metavis1/.../Core/Noise.metal`
**Algorithm:** Simplex & Interleaved Gradient
**Key Capabilities:**
*   **Simplex Noise:** A fast, high-quality 2D noise used for organic textures.
*   **Interleaved Gradient Noise (IGN):** A high-frequency constructive noise used specifically for **Dithering**. This is critical for the Volumetric Fog and Bloom shaders to prevent banding without using expensive blue noise textures.

### C. Macbeth Validation
**Source:** `metavis3/.../MacbethGenerator.swift`
**Tool:** Synthetic Chart Generator
**Key Capabilities:**
*   Generates the standard 24-patch Macbeth ColorChecker.
*   Uses linear sRGB reference values.
*   *Usage:* Validating that the ACES pipeline doesn't drift colors unexpectedly.

## 3. Integration Plan

These libraries are the "Standard Library" for all our shaders.

1.  **Port `ACES.metal` and `Noise.metal`** to `MetaVisGraphics/Shaders/Core/`.
    *   *Constraint:* These must be available to *every* other shader via `#include`.
2.  **Port `MacbethGenerator`** to `MetaVisQC` for automated color validation tests.
