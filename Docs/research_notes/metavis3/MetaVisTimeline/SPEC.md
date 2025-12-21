# MetaVisTimeline Specification

## Overview
MetaVisTimeline is the "Sequencer" of the Virtual Studio. It manages the temporal arrangement of media, effects, and device instructions. It is the single source of truth for the `MetaVisSession`.

## 1. Session & State Management
**Goal:** Host the `MetaVisSession` and manage the lifecycle of the project.

### Components
*   **`MetaVisSession`:** The root object.
*   **`Timeline`:** The container for Tracks and Clips.
*   **`DeviceManager`:** Manages the list of active `VirtualDevices` in the session.

### Implementation Plan
*   [x] `MetaVisSession` implemented.
*   [ ] Integrate `DeviceManager` into Session.

## 2. Device Tracks
**Goal:** Allow keyframing of Device properties (e.g., animating Camera ISO or Light Intensity).

### Data Structures
*   **`DeviceTrack` (Class):**
    *   Inherits from `Track`.
    *   Target: A specific `VirtualDevice.id`.
    *   Content: Keyframes for specific properties (e.g., "iso" curve).

### Implementation Plan
*   [ ] Create `DeviceTrack` class.
*   [ ] Update `TimelineResolver` to resolve Device Tracks into a `DeviceState` stream.

## 3. Graph Building (The Bridge)
**Goal:** Convert the high-level Timeline + Scene State into a low-level `NodeGraph` for the Engine.

### Components
*   **`TimelineGraphBuilder`:**
    *   **Input:** `Timeline`, `SceneState`.
    *   **Output:** `NodeGraph`.
    *   **Logic:**
        1.  Resolve Clips -> Source Nodes.
        2.  Resolve Effects -> Effect Nodes.
        3.  **New:** Resolve `SceneState.activeCamera` -> Camera/Lens Nodes.
        4.  **New:** Resolve `SceneState.environment` -> Relighting/Reverb Nodes.

### Implementation Plan
*   [ ] Update `TimelineGraphBuilder` to accept `SceneState`.
*   [ ] Implement logic to inject Camera/Lens nodes based on the active device.
