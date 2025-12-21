# Research Note: Audio Architecture (Analysis of Gap)

**Source Documents:**
- `MetaVisAudio/Sources/` (Empty except for `AudioLoader.swift`)
- `MetaVisAudio/SPEC.md` (Aspiration only)

## 1. Executive Summary
**Status: CRITICAL GAP.**
The legacy `MetaVisAudio` package is effectively empty. It contains a basic `AudioLoader` but **no engine, no mixer, and no synchronization logic**. 

MetaVisKit2 must implement the audio subsystem from scratch.

## 2. Existing Artifacts
-   **`AudioLoader.swift`**: Wraps `AVAssetReader` to pull PCM buffers. Basic utility.
-   **`SPEC.md`**: Outlines a desire for:
    -   Spatial Audio (Reverb, 3D Positioning).
    -   Generative Voice (11Labs integration).

## 3. Architecture for MetaVisKit2
Since we are building from scratch, we should adopt a modern **Processing Graph** approach similar to the Video pipeline.

### A. The Audio Session
-   **`AudioEngine`**: Wrapper around `AVAudioEngine`.
-   **`MixerGraph`**: A dynamic `AVAudioMixerNode` graph mirroring the `Timeline` tracks.
    -   Track 1 (Video) -> Mixer Input 1
    -   Track 2 (Music) -> Mixer Input 2

### B. Synchronization
 This is the hardest part of any NLE.
-   **Strategy:** Driven by the `RenderEngine` clock.
-   **Preview:** In "Edit Mode", the Audio Engine drives the clock (video syncs to audio).
-   **Render:** In "Export Mode", audio is pulled sample-by-sample to match video frames.

### C. Logic Required
1.  **`AudioGraphBuilder`**: Counterpart to `TimelineGraphBuilder`. Converts `Timeline` -> `AVAudioEngine` connection graph.
2.  **`AudioUnit` Wrapper**: Support for VST/AU plugins (future proofing).

## 4. Synthesis
-   **Reuse:** Nothing to reuse.
-   **Plan:** Must build `MetaVisAudio` as a core pillar of typical NLE functionality (Sprint 12 Priority).
