# MetaVisCalibration Specification

## Overview
MetaVisCalibration ensures that the "Virtual World" matches the "Real World." It handles lens calibration, color profiling, and sensor fusion alignment.

## 1. Lens Calibration
**Goal:** Correct physical lens distortion to match the virtual camera.

### Components
*   **`LensProfiler`:**
    *   Analyzes checkerboard patterns to generate distortion maps.
    *   Used by `MetaVisIngest` to tag clips with lens metadata.

### Implementation Plan
*   [ ] Implement `LensProfiler`.

## 2. Color Calibration
**Goal:** Ensure color accuracy across devices.

### Components
*   **`ColorChecker`:**
    *   Analyzes Macbeth charts to generate IDTs (Input Device Transforms).

### Implementation Plan
*   [ ] Implement `ColorChecker`.
