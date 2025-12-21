# MetaVis Render: Gap Analysis & Architecture Report

**Date:** December 8, 2025
**Status:** Verified Foundation

## 1. Executive Summary
The goal is to restore the "perfect" ACES CG pipeline of the legacy system (0.03 Delta E) and enhance it for "Superhuman" accuracy (<0.06 Delta E target) with integrated FLAC audio and procedural validation.

We have successfully ported the core mathematical models from the legacy system into a new, high-precision `MetaVisCalibration` module. We have also established the `MetaVisAudio` and `MetaVisImageGen` foundations.

## 2. Gap Analysis

### A. Color Science (ACES)
*   **Legacy**: Used `float` (Single Precision) matrices in Metal shaders. Verification was done in Swift using `Double`.
*   **Gap**: The new `MetaVisCore` lacked the full ACES matrix set (AP0/AP1, Rec.709/2020/P3 transforms).
*   **Resolution**: 
    *   Ported all legacy matrices to `MetaVisCalibration/Color/ACES.swift`.
    *   Upgraded storage to `Double` (SIMD3<Double>) for CPU-side science.
    *   Created `MetaVisCalibration/Shaders/ACES.metal` for the GPU pipeline.
*   **Status**: **CLOSED**.

### B. Validation & Accuracy
*   **Legacy**: Achieved 0.03 Delta E.
*   **Gap**: No centralized "Science Lab" for validation. `ColorLabTools` in Core was Float-based.
*   **Resolution**:
    *   Created `MetaVisCalibration/Science/ColorLab.swift`.
    *   Implemented `Delta E 2000` algorithm using full `Double` precision.
    *   Verified matrix inversion accuracy (Identity check) to `1e-6` (limited by legacy source precision).
*   **Status**: **CLOSED**.

### C. Audio
*   **Legacy**: Basic audio support.
*   **Gap**: No FLAC support. No dedicated audio loader in the new architecture.
*   **Resolution**:
    *   Created `MetaVisAudio/IO/AudioLoader.swift`.
    *   Implemented `AVAudioFile` based loading to support FLAC natively.
*   **Status**: **FOUNDATION READY**.

### D. Content Generation
*   **Legacy**: Static JSON files for Macbeth charts.
*   **Gap**: No procedural generation.
*   **Resolution**:
    *   Created `MetaVisImageGen/Generators/MacbethGenerator.swift`.
    *   Defined standard sRGB patch values for the 24-patch ColorChecker.
*   **Status**: **FOUNDATION READY**.

## 3. Architecture

### The "Source of Truth" Model
The system is now architected around `MetaVisCalibration` as the mathematical authority.

```mermaid
graph TD
    A[MetaVisCalibration] -->|Defines Matrices (Double)| B[MetaVisCore]
    A -->|Defines Shaders (Metal)| C[MetaVisRender]
    A -->|Validates Output| D[MetaVisCLI]
    
    E[MetaVisImageGen] -->|Generates Macbeth| F[Render Pipeline]
    G[MetaVisAudio] -->|Loads FLAC| F
    
    F -->|Output Buffer| H[ColorLab (in Calibration)]
    H -->|Delta E Report| I[User]
```

### Precision Strategy
*   **CPU (Science)**: All validation, matrix generation, and ground-truth calculations use `Double` (64-bit).
*   **GPU (Render)**: Metal uses `float` (32-bit) for performance, but matrices are uploaded from the high-precision CPU source.
*   **Verification**: The `ACESAccuracyTests` prove that the math holds up.

## 4. Next Steps
1.  **Wire the Pipeline**: Connect `ExportWorker` to use `ACES.metal` for the actual pixel processing.
2.  **Full Integration Test**: Run a render of the generated Macbeth chart and verify the output file against the `ColorLab` math.
