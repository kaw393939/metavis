# MetaVisPerception - Legacy Code References

This document tracks the legacy analysis tools that enable the "Scientific Method" for AI development.

## AI Analysis (Probabilistic)
*   **`metavis_render/Sources/MetaVisRender/Analysis/GeminiAnalyzer.swift`**
    *   **Description**: The bridge to Gemini 2.0 Flash (to be upgraded to 3.0 Pro).
    *   **Key Features**:
        *   **System Prompts**: Pre-engineered prompts for "Render Quality", "Color Accuracy", "Artifact Detection", and "Motion Smoothness".
        *   **Structured Output**: JSON-formatted responses (e.g., `{"analysis": "...", "grade": "A+"}`) for automated parsing.
    *   **Why it's valuable**: Enables qualitative feedback ("This looks good") in an automated pipeline.

## Deterministic Analysis (Math)
*   **`metavis_render/Sources/MetaVisRender/Analysis/QualityAnalyzer.swift`**
    *   **Description**: Measures objective image quality metrics.
    *   **Key Features**:
        *   **Sharpness**: Uses Laplacian variance to detect blur.
        *   **Noise**: Estimates Signal-to-Noise Ratio (SNR).
        *   **Contrast**: RMS Contrast measurement.
    *   **Why it's valuable**: Provides hard numbers to back up the AI's qualitative assessment.

*   **`metavis_render/Sources/MetaVisRender/Analysis/MotionAnalyzer.swift`**
    *   **Description**: Analyzes temporal stability.
    *   **Key Features**: Optical flow calculation, Jitter/Stutter detection.
    *   **Why it's valuable**: Ensures the simulation runs smoothly without dropped frames or temporal artifacts.

*   **`metavis_render/Sources/MetaVisCLI/DiagnoseCommand.swift`**
    *   **Description**: System health and capability profiling.
    *   **Key Features**: ANE verification, GPU profiling.
