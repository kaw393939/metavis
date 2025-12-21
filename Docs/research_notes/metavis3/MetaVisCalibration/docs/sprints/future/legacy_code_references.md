# MetaVisCalibration - Legacy Code References

This document tracks the critical legacy code that must be ported to preserve the "Superhuman" color pipeline and scientific accuracy.

## Core Color Science (ACES / ODT)
**Critical Priority**: This logic defines the visual look and mathematical correctness of the entire system.

*   **`metavis_render/Sources/MetaVisRender/Shaders/ColorSpace.metal`**
    *   **Description**: The single source of truth for color space definitions, encodings, and gamut transforms.
    *   **Key Features**:
        *   **ACES Matrices**: `M_ACEScg_to_XYZ`, `M_AP0_to_XYZ` (D60 white point).
        *   **Bradford CAT**: `M_CAT_D65_to_D60` for correct chromatic adaptation between Rec.709 (D65) and ACES (D60).
        *   **Transfer Functions**:
            *   `PQToLinearNits`: ST.2084 EOTF optimized for 10,000 nits peak.
            *   `HLGToLinear`: ARIB STD-B67 implementation.
            *   `AppleLogToLinear`: Custom approximation for Apple Log profile.
    *   **Why it's valuable**: Contains the optimized 16-bit float math for Apple Silicon GPUs.

*   **`metavis_render/Sources/MetaVisCLI/ValidateColorCommand.swift`**
    *   **Description**: The CLI command used to validate color accuracy against SMPTE/ISO standards.
    *   **Key Features**: `LabColor` struct implementation, Delta E calculation logic.
    *   **Why it's valuable**: Provides the mathematical proof that the renderer is accurate.

## Validation Logic

*   **`metavis_render/Sources/MetaVisRender/Analysis/ColorAnalyzer.swift`**
    *   **Description**: Analyzes rendered frames for color accuracy and neutrality.
    *   **Key Features**: Frame extraction, statistical analysis of color channels.
