# Sprint 27: Cinematic Text Engine (SDF + PBR)

## Goal
Upgrade the text rendering from "Flat Overlay" to "Physical Object" by implementing High-Resolution Multi-channel Signed Distance Fields (MSDF) integrated with the PBR lighting system.

## Rationale
To create "Marvel-style" openers or "Apple-style" kinetic typography, text cannot just be white pixels. It must be able to reflect the environment, have bevels (via normal mapping), and cast soft shadows.

## Deliverables
1.  **`SDFGenerator`:** A tool to generate MSDF texture atlases from system fonts.
2.  **`TextPBR.metal`:** A variant of the PBR shader that uses SDF derivatives to compute normals (bevels) and alpha (shape).
3.  **`Text3D` Component:** A high-level component exposing `text`, `font`, and `material` (e.g., Gold).
4.  **Zoom Test:** Verify text remains crisp at 10x visual scale.

## Optimization: Apple Silicon
*   **MTSDF:** Use Multi-Channel Signed Distance Fields (MTSDF) to preserve sharp corners.
*   **PBR Integration:** Ensure `TextPBR.metal` calls the atomic functions in `BSDF.metal` (Sprint 26) to maintain lighting consistency with the rest of the scene.

## Sources
- `Docs/specs/advanced_features_research/spec_text_pbr.md`
