# Legacy AI & Audio Extraction Report

**Date:** 2025-12-20
**Scope:** `metavis2` (AI/Audio), `metavis3` (ImageGen), `metavis4` (Scheduler)
**Status:** COMPLETE

## 1. Executive Summary
Beyond the visual rendering features, we have uncovered a sophisticated suite of **AI-driven Audio Tools** and a **Deterministic Procedural Image Generator (LIGM)**.

These features enable "Smart Editing" (auto-sync, stem splitting) and "Infinite Content" (procedural textures/starframes).

## 2. Feature Deep Dive

### A. AI Source Separation
**Source:** `metavis2/.../AdvancedAI/SourceSeparator.swift`
**Model:** Demucs-style Neural Network (Simplified invocation in Swift)
**Key Capabilities:**
*   **4-Stem Separation:** Splits audio into `Dialog`, `Music`, `Ambience`, and `Other`.
*   **Quality Metrics:** Calculates inter-stem correlation to estimate separation quality (lower correlation = better split).
*   **Music Construction:** Automatically mixes Drums + Bass into the Music stem.
*   **Ambience Extraction:** Uses low-frequency heuristic to split "Other" into Ambience vs Effects.

### B. Multi-Camera Synchronization
**Source:** `metavis2/.../AdvancedAI/MultiCamSyncEngine.swift`
**Algorithm:** Audio Fingerprinting (Chromagrams) + Waveform Cross-Correlation
**Key Capabilities:**
*   **Fingerprinting:** Extracts Chromagrams (pitch class energy) and RMS energy from audio tracks.
*   **Drift Detection:** Compares start and end correlation to detect clock drift between cameras.
*   **Auto-Cut Suggestions:** Can suggest cuts based on "Speaker Changes" (diarization) or "Reaction Shots" (emotion intensity).
*   **Robustness:** Fallback mechanism: Chromagram (Course) -> Waveform (Fine).

### C. LIGM (Lost Image Generation Model)
**Source:** `metavis2/.../ImageGen/LIGMProceduralBackend.swift` (and `metavis3` references)
**Algorithm:** Deterministic Procedural Generation
**Key Capabilities:**
*   **Deterministic RNG:** Uses a seeded `Xorshift64` generator to ensure `Seed: 12345` always produces the exact same image pixel-for-pixel.
*   **Primitives:**
    *   **FBM:** Fractal Brownian Motion for clouds/terrain.
    *   **Domain Warp:** Distorted noise for fluid-like patterns.
    *   **Hubble Preprocess:** Specific multi-scale noise for astronomical accumulation maps.
    *   **SDF:** Signed Distance Fields for perfect geometric shapes (Circles, Boxes, Stars).
*   **Output:** Generates `Float32` linear buffers (ACEScg ready), converted to `Float16` Metal textures.

### D. Spatial Audio Export
**Source:** `metavis2/.../Spatial/MultichannelExporter.swift`
**Algorithm:** Vector Base Amplitude Panning (VBAP)
**Key Capabilities:**
*   **Formats:** 5.1, 7.1, Stereo.
*   **Logic:** Maps 3D positions (Azimuth/Elevation) to speaker gains.
*   **LFE:** Automatic Low-Frequency Effects routing based on distance.

## 3. Integration Plan

### Phase 1: The "Brain" (Sprint 04+)
1.  **Port `SourceSeparator`** to `MetaVisPerception`.
    *   *Usage:* Auto-tagging audio clips in the bin.
2.  **Port `MultiCamSyncEngine`** to `MetaVisSession`.
    *   *Usage:* "Sync Bin" feature.

### Phase 2: The "Forge" (Sprint 08+)
3.  **Port `LIGMProceduralBackend`** to `MetaVisImageGen`.
    *   *Usage:* Generating test patterns, star fields, and noise textures for the PBR engine.

### Phase 3: The "Voice" (Sprint 12+)
4.  **Port `MultichannelExporter`** to `MetaVisExport`.
    *   *Usage:* Final delivery of theatrical mixes.
