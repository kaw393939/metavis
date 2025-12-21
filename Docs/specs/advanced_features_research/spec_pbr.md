# Spec: Physically Based Rendering (Disney Model)

## 1. Objective
Implement a "Cinematic" lighting model based on the **Disney Principled BRDF** (2012) to serve as the standard material system for `MetaVisKit2` 3D elements (Titles, 3D Models, Particles).

## 2. Mathematical Definition
The shader will implement the following components adapted from `metavis1/Sources/MetalVisCore/Shaders/Materials/PBR.metal`.

### 2.1 Inputs (Surface)
*   `BaseColor` (Linear ACEScg)
*   `Metallic` (0-1)
*   `Roughness` (0-1)
*   `Specular` (0-1, default 0.5)
*   `IOR` (Index of Refraction, default 1.5)
*   `Transmission` (0-1, for glass)
*   `Sheen` / `SheenTint` (Cloth)
*   `Clearcoat` / `ClearcoatGloss` (Coated materials)

### 2.2 BRDF Terminology
*   **D** (Distribution): `GTR2` (Generalized Trowbridge-Reitz 2) for the primary specular lobe.
*   **F** (Fresnel): `Schlick` approximation.
    *   `F0` logic: `mix(0.04, BaseColor, Metallic)` (Dielectrics use 0.04, Metals use BaseColor).
*   **G** (Geometry): `SmithG_GGX` (Smith Shadowing-Masking function).

### 2.3 Lighting
*   **Direct:** Analytical Sphere/Rect lights (Area lights) approximations.
*   **Indirect (IBL):** Split-Sum Approximation (DFG LUT + Prefiltered Environment Map). *Note: Legacy code did not fully implement IBL; this will be a new addition for v2.*

## 3. Implementation Plan
1.  **Shader Library**: Create `Sources/MetaVisGraphics/Shaders/BSDF.metal` containing the atomic functions (`GTR1`, `GTR2`, `SmithGGX`, `Fresnel`).
2.  **Material Shader**: Create `Sources/MetaVisGraphics/Shaders/PBR.metal` using the library.
3.  **Swift Structs**: Create `PBRMaterial` struct in `MetaVisGraphics` that matches the buffer layout.

## 4. Acceptance Criteria
*   **Metalness Workflow**: Pure metal (`Metallic=1, Roughness=0`) looks like a mirror.
*   **Dielectric Workflow**: Plastic (`Metallic=0, Roughness=0`) looks shiny but with white specular highlights.
*   **Energy Conservation**: The output pixel should never exceed incoming energy (unless Emissive).
*   **Reference Match**: Output should visually match the reference renderings from `metavis1`.
