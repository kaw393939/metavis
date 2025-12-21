# Legacy Extraction Report: The "Lost" Features

**Date:** 2025-12-20
**Scope:** `metavis1` ... `metavis4`
**Status:** COMPLETE

## 1. Executive Summary
We have successfully located and analyzed the source code for the advanced features referenced in the "Legacy Mining" prompts. The legacy codebase (`metavis1/Sources/MetalVisCore`) contains production-grade implementations of **Volumetric Raymarching**, **Disney PBR**, **ACES Color Science**, and **GPU Graph Layout**.

These features are currently missing from `MetaVisKit2` and should be ported immediately to reach parity with the "World's Finest Version."

## 2. Feature Deep Dive

### A. Disney Principled Material System ("Disney Render")
**Source:** `metavis1/.../Shaders/Materials/PBR.metal`
**Algorithm:** Disney Principled BRDF (Burley 2012)
**Key Capabilities:**
*   **Physically Based Parameters:** BaseColor, Metallic, Roughness, Specular, Sheen, Clearcoat.
*   **Math:** Uses `SchlickFresnel` for F0 and `GTR2` (Generalized Trowbridge-Reitz) for specular distribution.
*   **Energy Conservation:** Strictly enforced.
*   **Integration:** Designed to work with a Deferred or Forward cluster renderer (Uniforms match Swift structs 1:1).

### B. Volumetric Nebula Engine ("Fluid")
**Source:** `metavis1/.../Shaders/Effects/VolumetricNebula.metal`
**Algorithm:** Raymarching with Henyey-Greenstein Phase Function
**Key Capabilities:**
*   **True Volumetrics:** Not 2D sprites. Raymarches through a 3D FBM density field.
*   **Lighting:** Self-shadowing (shadow rays march towards light) and Anisotropic scattering (forward/back scattering via `phaseG`).
*   **Compositing:** Reads the Scene Depth buffer (`texture(0)`) to correctly occlude the volume behind geometric objects (e.g., mountains).
*   **Note:** This is *not* a Navier-Stokes fluid solver. It is a "Procedural Fluid" system using 3D Noise, which is far more efficient for large-scale effects (Clouds, Nebulas) than grid simulation.

### C. "Superhuman" Color Science
**Source:** `metavis1/.../Shaders/ColorSpace.metal`
**Algorithm:** ACES (Academy Color Encoding System)
**Key Capabilities:**
*   **Gamut Awareness:** Native support for ACEScg, Rec.2020, P3-D65.
*   **Chromatic Adaptation:** Implements Bradford D65<->D60 matrices to correctly handle white points.
*   **HDR Transfer Functions:** Native `PQ` (Perceptual Quantizer) and `HLG` support.
*   **Status:** This is the most critical file to port. It ensures `MetaVisKit2` is "HDR Ready."

### D. GPU Graph Layout
**Source:** `metavis1/.../Shaders/GraphLayout.metal`
**Algorithm:** Barnes-Hut Force Directed Layout
**Key Capabilities:**
*   **Parallelism:** Uses Compute Kernels to solve N-body physics for graph nodes.
*   **Performance:** Stack-based QuadTree traversal on GPU allowing 10k+ nodes @ 60fps.
*   **Use Case:** Large scale node graphs, timeline visualizations, or "Knowledge Brain" UI.

## 3. Porting Roadmap

### Phase 1: Foundations (Sprint 03+)
1.  **Port `ColorSpace.metal`** to `MetaVisGraphics/Shaders/Library/`.
    *   *Why:* Everything else depends on the `DecodeToACEScg` function.
2.  **Port `SDFText.metal`** to `MetaVisGraphics/Shaders/Text/`.
    *   *Why:* UI needs text.

### Phase 2: The Look (Sprint 10+)
3.  **Port `PBR.metal`** to `MetaVisGraphics/Shaders/Material/`.
4.  **Port `Bloom.metal`** and `Lens.metal` to `MetaVisGraphics/Shaders/Effects/`.

### Phase 3: The Magic (Sprint 15+)
5.  **Port `VolumetricNebula.metal`**.
    *   This requires a `VolumetricPass` in the Render Graph.
6.  **Port `GraphLayout.metal`**.
    *   Only needed if we build a "Node Editor" UI.
