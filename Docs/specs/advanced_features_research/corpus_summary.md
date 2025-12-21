# Deep Dive Research: Advanced Features from Legacy MetaVis

**Date:** 2025-12-20
**Source Material:** `metavis1`, `metavis2`, `metavis3`, `metavis4` (Research Notes)

## Executive Summary
This document synthesizes the advanced rendering capabilities found in previous versions of the engine. These features represent "Golden Standard" implementations of high-end graphical techniques (Disney PBR, Fluid Dynamics, SDF Text) that were verified in previous iterations but have not yet been ported to `MetaVisKit2`.

The goal is to re-integrate these features to create the "World's Finest Version" running on Apple Silicon.

## 1. Disney Principled BRDF ("Disney Render")
**Source:** `metavis1/.../PBR.metal`
**Status:** **Production Ready (Legacy)**

The legacy engine implemented a subset of the **Disney Principled BRDF** (Bidirectional Reflectance Distribution Function), aiming for cinematic physical realism.

*   **Core Math:**
    *   **Fresnel:** `SchlickFresnel` (Approximation for F0).
    *   **Specular Distribution:** `GTR1`, `GTR2` (Generalized Trowbridge-Reitz).
    *   **Geometric Shadowing:** `SmithG_GGX`.
*   **Material Parameters:**
    *   Base Color, Metallic, Roughness, Specular.
    *   **Sheen / SheenTint:** For cloth/fabric simulation.
    *   **Clearcoat / ClearcoatGloss:** For car paint / varnished wood.
    *   **Transmission / IOR:** For glass/water (refraction).
    *   **Emission:** Physically based intensity (Blackbody support).

## 2. Text / SDF Rendering
**Source:** `metavis1/.../SDFText.metal`
**Status:** **High Quality (Legacy)**

Text rendering uses **Multi-channel Signed Distance Fields (MSDF)**, allowing for infinite scalability without pixelation.

*   **Technique:**
    *   **MSDF:** Encodes shape corners in RGB channels to preserve sharp edges better than standard SDF.
    *   **Derivatives:** Uses `dfdx`/`dfdy` screen-space derivatives to calculate anti-aliasing width dynamically based on zoom level.
    *   **Features:** Sub-pixel anti-aliasing (3x horizontal resolution), soft dropshadows, and outlines.
*   **PBR Integration:** Although not explicitly seen in the shader, the SDF output (Alpha/Shape) can easily drive the Roughness/Metallic maps of the PBR shader to create "Gold Lettering" or "Neon Signs".

## 3. Fluid Simulation (Particles & Curl Noise)
**Source:** `metavis1/.../Particles.metal`
**Status:** **Procedural (Legacy)**

References to a "Fluid" system appear to rely on **Curl Noise Turbulence** rather than a full Navier-Stokes grid simulation (which is heavy for real-time 4K).

*   **Technique:**
    *   **Curl Noise:** Calculates the curl of a Simplex noise field to create divergence-free vector fields. This guarantees that particles move in "swirly," fluid-like paths without needing a pressure solver.
    *   **Simulation:** Vertex Shader-driven.
    *   **Blackbody Radiation:** Maps temperature (Kelvin) to RGB color for realistic fire/magma effects.
    *   **Buoyancy:** Particles rise based on temperature/phase.

## 4. Cinematic VFX
**Source:** `legacy_vfx_ai_mining.md`, `Lens.metal`, `Bloom.metal`

The legacy stack included a suite of cinematic optical effects:
*   **Bloom:** Jimenez "Next Gen" Bloom with Karis Average (stability) and Golden Angle upsampling (bokeh-like).
*   **Lens Distortion:** Brown-Conrady physical distortion coupled with Chromatic Aberration.
*   **Film Grain:** Simplex noise-based overlay.

## Recommended Porting Strategy
1.  **MetaVisGraphics**: Create a unified `Shaders/Library` containing `PBR.metal` and `SDF.metal`.
2.  **MetaVisFX**: Port the `Particles.metal` into a `ParticleSystem` node.
3.  **MetaVisText**: Port the `SDFTextRenderer` logic.
