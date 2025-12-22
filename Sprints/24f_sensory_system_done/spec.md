# Sprint 24f: Sensory System - Specification

**Goal:** Ensure the system can see and hear reliably, efficiently, and with nuance.

## Objectives

1.  **Multi-Speaker Discrimination (Priority P0)**
    *   **Problem:** `BiteMapBuilder` currently attributes all speech to the first observed face ("P0"), merging overlapping speakers into a single timeline.
    *   **Requirement:** Update `BiteMapBuilder` to attribute each bite window to the most likely `personId` when multiple faces are present in `MasterSensors.videoSamples`.
        *   Prefer deterministic, already-available evidence (e.g. `Face.mouthOpenRatio`, face presence/area/center bias).
        *   Do not introduce new ML models in this sprint.
    *   **Success Metric:** For a two-person fixture with alternating speakers, `BiteMap.bites` contains bites with at least two distinct `personId` values.

2.  **Memory-Safe Audio Analysis (Priority P1)**
    *   **Problem:** `MasterSensorIngestor` buffers mono samples in memory for the analyzed window (bounded by `audioAnalyzeSeconds`). Large values can still cause high memory use.
    *   **Requirement:** Refactor `readAudioAnalysis` to reduce peak memory, ideally by chunking/streaming audio through the analysis pipeline.
    *   **Success Metric:** Peak audio buffer memory scales with chunk size, not total analyzed duration.

3.  **QC Optimization (Priority P2)**
    *   **Problem:** `SourceContentHashV1` is computed (for stable IDs) but the hash is not persisted in the sensors artifact.
    *   **Requirement:** Persist the source content hash into `MasterSensors.source` (optional field) so downstream QC/export can rely on it without recomputation.
    *   **Success Metric:** `MasterSensors.source` includes a content hash (stable across machines/renames) for every ingest.

4.  **Error Hygiene (Priority P3)**
    *   **Problem:** `VideoQC` throws `NSError` with "magic number" codes.
    *   **Requirement:** Define a proper `QCError` enum conforming to `LocalizedError`.
    *   **Success Metric:** Errors printed in logs are human-readable (e.g., "FrameDropThresholdExceeded" instead of "Error 402").

5.  **Sensory Tuning (Priority P3)**
    *   **Problem:** `AudioVADHeuristics` uses hardcoded magic numbers (RMS -45dB) which fails in noisy environments.
    *   **Requirement:** Move thresholds to a `VADConfiguration` struct.
    *   **Success Metric:** Can adjust VAD sensitivity via config without recompiling.

## Scope Changes
*   **Clarification:** This sprint is not about building a diarization model from scratch. Focus on reliability, evidence windows, and data-structure support for multi-speaker attribution using the diarization and tracking capabilities present in the repo.
