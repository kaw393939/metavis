# MetaVisAudio Specification

## Overview
MetaVisAudio handles the audio processing pipeline. It treats audio as a spatial element in the Virtual Set, supporting reverb, spatialization, and generative voice.

## 1. Spatial Audio
**Goal:** Simulate the acoustic environment.

### Components
*   **`ReverbNode`:**
    *   Applies Impulse Responses (IR) based on `SceneState.environment`.
*   **`SpatializerNode`:**
    *   Positions audio sources in 3D space relative to the `ActiveCamera`.

### Implementation Plan
*   [ ] Implement `ReverbNode`.
*   [ ] Implement `SpatializerNode`.

## 2. Generative Audio
**Goal:** Support AI Voice and Sound Effects.

### Components
*   **`VoiceGenerator`:**
    *   Interface for 11Labs/OpenAI TTS.
    *   Managed by `GeneratorDevice`.

### Implementation Plan
*   [ ] Implement `VoiceGenerator` interface.
