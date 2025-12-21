# MetaVisSimulation - Specification

## Goals
1.  Integrate the legacy "Cinematic Look" (Bloom, Grain, ACES) into the new engine.
2.  Implement the Zero-Copy Export pipeline.
3.  Support SDF Text rendering.

## Requirements

### Rendering
- Must support 16-bit Float HDR pipeline throughout.
- Must implement the ACES Output Device Transform (ODT) as the final step.
- **Cinematic Pass**: Must implement the full 12-stage pipeline from `CinematicLookPass.swift`:
    1.  Lens Distortion
    2.  Face Enhance (AI)
    3.  Bloom
    4.  Halation
    5.  Anamorphic Streaks
    6.  Composite
    7.  Light Leaks
    8.  Diffusion
    9.  Color Grading (LUT)
    10. Tone Mapping
    11. Vignette
    12. Film Grain

### Export
- Must support HEVC Main10 profile (10-bit color).
- Must support ProRes 422 HQ and 4444.
- **Zero-Copy**: Must use `CVPixelBufferPool` with `kCVPixelBufferMetalCompatibilityKey` and `kIOSurfacePixelFormat` to avoid CPU copies.
- **Color Space Metadata**: Must attach correct CVImageBuffer color primaries (P3/Rec.2020) and transfer functions (PQ/HLG) to the output file.

### Text
- Must render text using Signed Distance Fields (SDF) for crisp edges at any zoom level.
