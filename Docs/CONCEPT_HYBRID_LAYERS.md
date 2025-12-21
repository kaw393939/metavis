# Concept: The Hybrid Layer Architecture

> **The Big Picture**: A MetaVis `Track` is not just a container for video clips. It is a **Signal Path** that carries data through time.

## 1. The Spectrum of Content
We are dealing with a new paradigm where "Media" falls into three buckets:

### A. Deterministic (The "Real")
*   **Examples**: Camera footage (`.mov`), Recorded Audio (`.wav`).
*   **Characteristic**: Immutable hard interaction. 100% reproducible.
*   **Storage**: Disk / S3.

### B. Generative Frozen (The "Cached")
*   **Examples**: A LIGM generated image that has been "baked".
*   **Characteristic**: Created by AI, but now treated as a deterministic file.
*   **Storage**: Disk (Artifact cache).

### C. Generative Live (The "Fluid")
*   **Examples**: A `ParticleSystem`, a `Prompt` ("A storm ocean"), A `VirtualCamera` move.
*   **Characteristic**: A recipe that is simulated at render time. Can be non-deterministic unless seeded.
*   **Storage**: Metadata (JSON Recipe).

## 2. The Unified Track Model
Instead of separate "Video Tracks" and "Audio Tracks", we propose **Typed Signal Tracks**.

### The `Signal` Protocol
Every clip on a timeline emits a `Signal` at time $T$.
*   **Video Signal**: `ImageBuffer` (Color + Alpha + Depth).
*   **Audio Signal**: `PCMBuffer` (Samples).
*   **Control Signal**: `ParameterValue` (e.g., "Intensity = 0.8").

### Polymorphic Clips
A `Clip` holds a `Source`.
```swift
enum ClipSource {
    case asset(AssetReference)       // Deterministic / Frozen
    case generator(DeviceID, Prompt) // Live Generative
    case effect(EffectID)            // Signal Modifier
}
```

## 3. Composition: Layers vs. Nodes
*   **Layers (NLE Style)**: Track 2 blends on top of Track 1. Simple, intuitive.
*   **Nodes (Compositor Style)**: Signals are routed together. Powerful, complex.
*   **MetaVis Approach**: **"Stacked Compositing"**.
    *   Tracks are layers.
    *   BUT, a Track can be a "Sub-Flow" (Pre-comp) that contains its own internal logic.

## 4. The "Virtual Set" Metaphor
This aligns with our `VirtualDevice` architecture.
*   **Track 1 (Background)**: A generative `LIGMDevice` creating a "Sci-Fi City".
*   **Track 2 (Action)**: A deterministic `CameraDevice` footage of an actor.
*   **Track 3 (Lighting)**: A control track sending DMX signals to physical lights.
*   **Track 4 (Audio)**: A generative `AudioDevice` creating spatial ambience.

## 5. Summary
We move away from "Editing Video" to "Orchestrating Signals".
*   **Asset**: Just one type of Signal Source.
*   **Prompt**: Another type of Signal Source.
*   **Render**: The act of sampling all signals at Time $T$ and resolving them.
