# MetaVisPerception Code Review

**Date:** 2025-12-21
**Reviewer:** Antigravity Agent
**Module:** `MetaVisPerception`

## 1. Executive Summary

`MetaVisPerception` is the sensory system of MetaVis. It ingests raw media and deterministicly produces structured metadata ("Sensors" and "Bites") that downstream AI agents and editors use to make decisions.

**Strengths:**
- **Determinism First:** The module goes to extreme lengths to ensure deterministic output. `MasterSensorIngestor` quantizes Vision rects, sorts results by geometry instead of UUID, and uses SHA256-derived stable IDs. This is critical for regression testing and stable editing.
- **Dependency Minimization:** It implements a full Audio VAD (Voice Activity Detector) and Music Detector using only `Accelerate` (vDSP), avoiding heavy CoreML audio models for basic segmentation.
- **Rich Heuristics:** `DescriptorBuilder` and `AutoStartHeuristics` encapuslate complex editorial logic (e.g., "punch-in suggestion") into simple JSON-serializable signals.

**Critical Gaps:**
- **Single Person Assumption:** `BiteMapBuilder` currently assumes the first face seen ("P0") is the speaker for all speech segments. This breaks for interviews or multi-cam footage.
- **Memory Usage:** `readAudioAnalysis` reads the entire audio track into memory arrays (`monoSamples`). For long-form content (>1 hour), this will be a memory hog. It should be streaming or chunked.
- **Hardcoded Constants:** `AudioVADHeuristics` contains magic numbers for thresholds (RMS -45dB, etc.) that might need to be exposed as configuration for different mic inputs.

---

## 2. Detailed Findings

### 2.1 Architecture (`MasterSensorIngestor`)
- **Pipeline:** Ingests AVAsset -> Reads Video Samples (Vision) & Audio Samples (Accelerate) -> Runs Heuristics -> Outputs `MasterSensors` struct.
- **Stability:** Explicit quantization of floats (Time, Rects, DB) prevents cross-architecture drift (e.g., x86 vs arm64 float micro-differences).

### 2.2 Detectors
- **Vision:** Uses `TracksDevice` (Face) and `MaskDevice` (Segmentation). It handles tracking re-acquisition seamlessly.
- **Audio:** `AudioVADHeuristics` uses ZCR (Zero Crossing Rate) and Spectral Flatness to distinguish Speech, Music, and Silence. This is a lightweight, classic DSP approach that is robust and fast.

### 2.3 Data Structures (`MasterSensors`, `Bites`)
- **JSON Serializable:** All outputs are simple structs, making them easy to debug and compatible with non-Swift tools (Python/Node).
- **Bites:** The `Bite` concept abstracts "a person speaking" into a distinct timeline object, which is the atomic unit for "A-Roll" editing.

---

## 3. Recommendations

1.  **Stream Audio Analysis:** Refactor `readAudioAnalysis` to process audio in chunks (e.g. 10s windows) to cap memory usage.
2.  **Multi-Speaker Bites:** Update `BiteMapBuilder` to use the `faces` data in `VideoSample` to attribute speech to the on-screen face, enabling basic speaker diarization.
3.  **Configuration Object:** Move magic numbers in `AudioVADHeuristics` to a `VADConfiguration` struct to allow tuning for noisy environments.
