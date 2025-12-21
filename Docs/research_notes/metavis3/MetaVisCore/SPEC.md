# MetaVisCore Specification

## Overview
MetaVisCore is the foundational module that defines the "Schema" of the Virtual Studio. It abstracts the complexity of rendering, hardware, and AI into a unified data model that Agents and Users can manipulate.

## 1. Virtual Device Abstraction
**Goal:** Treat every entity (Camera, Light, Screen, Generator) as a controllable device.

### Data Structures
*   **`VirtualDevice` (Protocol):**
    *   `id: UUID`
    *   `name: String`
    *   `type: DeviceType` (.camera, .light, .generator, .screen, .hardware)
    *   `properties: [String: NodeValue]` (The state: ISO, Intensity, Prompt)
    *   `actions: [String: ActionDefinition]` (The capabilities: "Record", "Strobe")
*   **`DeviceType` (Enum):**
    *   Extensible enum to categorize devices for the UI (e.g., "Show me all Lights").

### Implementation Plan
*   [x] Define `VirtualDevice` protocol.
*   [x] Define `DeviceType` enum.
*   [x] Implement `DeviceState` struct to snapshot a device at a specific time.

## 2. Spatial Context (Formerly Scene State)
**Goal:** Model the "Virtual Set" to give the Agent context for vague commands ("Make it darker").

### Data Structures
*   **`SpatialContext` (Struct):**
    *   `activeCameraId: UUID`
    *   `environment: EnvironmentProfile` (HDRI, Reverb IR)
    *   `location: LocationData` (GPS, Sun Position)
    *   `timeOfDay: Date`
*   **`LocationData` (Struct):**
    *   Latitude/Longitude, Compass Heading.
    *   Used for calculating physical sun position for relighting.

### Implementation Plan
*   [x] Create `SpatialContext` struct.
*   [x] Create `LocationData` struct.

## 3. Registry & Discovery
**Goal:** Allow Agents to discover what tools are available without hardcoding.

### Data Structures
*   **`NodeDefinition` (Existing):** Describes atomic render nodes.
*   **`Preset` (Existing):** Describes compound nodes (Macros).
*   **`LookAsset` (Existing):** Describes style transfer assets.
*   **`CastRegistry` (Existing):** Maps UUIDs to Person Names.

### Implementation Plan
*   [x] `NodeDefinition` implemented.
*   [x] `Preset` implemented.
*   [x] `LookAsset` implemented.
*   [x] `CastRegistry` implemented.

## 4. Session Management (Moved to MetaVisTimeline)
**Goal:** Manage the user's workspace and support "Shadow Timelines" for AI experimentation.

### Data Structures
*   **`MetaVisSession`:** Now resides in `MetaVisTimeline` module to support Timeline dependencies.
*   **`SessionController`:** Replaces the legacy `ProjectDocument` and `RenderManifest`.

### Implementation Plan
*   [x] `MetaVisSession` implemented in `MetaVisTimeline`.
*   [x] `SessionController` implemented in `MetaVisTimeline`.
*   [x] Legacy `RenderManifest` and `ProjectDocument` removed.
