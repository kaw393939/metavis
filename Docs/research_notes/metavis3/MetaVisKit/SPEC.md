# MetaVisKit Specification

## Overview
MetaVisKit is the "Glue" and the User Interface. It connects the User and the Agent to the `MetaVisSession`. It is responsible for the "Director's Viewfinder" experience.

## 1. Agent Interface
**Goal:** Provide a structured API for the LLM to control the system.

### Components
*   **`AgentInterface`:**
    *   Exposes `Session` actions as "Tools" (MCP-style).
    *   Handles "Vague to Specific" translation (using `SceneState`).
    *   Generates the `CapabilitiesManifest` (JSON of available devices/nodes).

### Implementation Plan
*   [ ] Implement `AgentInterface` class.
*   [ ] Implement `CapabilitiesManifest` generator.

## 2. Viewport & Interaction
**Goal:** Allow direct manipulation of the Virtual Set.

### Components
*   **`ViewportController`:**
    *   Renders the Engine output.
    *   Handles touch/mouse input.
    *   **New:** Maps gestures to `Device` actions (e.g., Pinch -> Zoom).
*   **`DeviceControlPanel`:**
    *   Dynamic UI that changes based on the selected `VirtualDevice` (Camera Rings vs. Light Sliders).

### Implementation Plan
*   [ ] Implement `ViewportController`.
*   [ ] Implement dynamic `DeviceControlPanel`.
