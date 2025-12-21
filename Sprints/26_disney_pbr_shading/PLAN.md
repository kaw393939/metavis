# Sprint 26: Disney Principled BRDF (The Skin)

## Goal
Implement the industry-standard **Disney Principled BRDF** (2012) lighting model to provide "Cinematic" rendering capabilities for all 3D surfaces in the engine.

## Rationale
Current rendering is basic. To achieve the "Masterpiece" look, we need materials that behave physically correctly (Energy Conservation, Fresnel, Microfacet Distribution). The Disney model is the standard for offline CGI (Pixar/Disney) and high-end games.

## Deliverables
1.  **`BSDF.metal`:** A library of atomic lighting functions (`GTR1`, `GTR2`, `SmithGGX`, `Schlick`).
2.  **`PBR.metal`:** The main surface shader integrating these terms.
3.  **`PBRMaterial`:** A Swift struct matching the GPU buffer layout (BaseColor, Metallic, Roughness, IOR, etc.).
4.  **Reference Scene:** A "Sphere Test" scene rendering Gold, Plastic, and Glass spheres.

## Optimization: Apple Silicon M3
*   **Opaque Optimization:** The `PBR.metal` implementation must rely on `setOpaqueTriangleIntersectionFunction` to strictly bypass "Any Hit" shaders for opaque materials (Metal/Dielectric). This doubles traversal performance on hardware raytracing units.

## Sources
- `Docs/specs/advanced_features_research/spec_pbr.md`
