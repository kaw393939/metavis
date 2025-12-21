# Research Note: MetaVisCore Architecture

**Source Documents:**
- `MetaVisCore/Data/` (NodeGraph, Asset)
- `MetaVisCore/Project/` (Project, ProjectGraph)
- `MetaVisCore/Devices/` (ACESDevice)

## 1. Executive Summary
`MetaVisCore` is the foundational data library. It is strictly **Model-centric**, providing robust data structures (`Project`, `Asset`, `NodeGraph`) but lacking **Controller** logic (Session management, State transitions). 

For MetaVisKit2, we should **keep the Data Models** (they are excellent) but build a new **Application Layer** on top to handle state.

## 2. Data Architecture (`Data` Module)
### A. The Generic Node Graph
-   **Implementation:** `NodeGraph`, `Node`, `Edge`.
-   **Features:**
    -   Type-safe ports (`PortType`).
    -   Cycle detection (`hasCycle`).
    -   Serialization support (`Codable`).
-   **Usage:** Crucial for the procedural effect graph (VFX) and potentially audio routing. It is generic enough to be reused.

### B. Asset Management
-   **`Asset`**: The source of truth for media.
-   **Key Capability:** `AssetRepresentation` (Original, Proxy, Stream).
    -   *Strategy:* MetaVisKit2 should leverage this for a "Proxy Workflow" (Fast edit with Proxy, Render with Original).
    -   *Self-Probing:* `Asset.init(from: URL)` handles AVFoundation probing automatically.

### C. Visual Analysis Data
-   **`VisualAnalysis`**: Stores AI results (Segmentation, Saliency) as metadata on the Asset.
-   **Design:** Decoupled from heavy data (masks referenced by UUID).

## 3. Project Architecture (`Project` Module)
### A. Recursive Dependencies
-   **`ProjectGraph`**: Allows projects to import other projects.
-   **Impact:** Enables "Nested Sequences" or "Master Projects".

### B. The "Session Gap"
-   **Missing:** `MetaVisCore/Session` is empty.
-   **Consequence:** There is no code to manage the *active* project, undo stack, or selection state. This logic currently lives (poorly) in the CLI or not at all.
-   **Requirement:** MetaVisKit2 must implement a `ProjectSession` actor.

## 4. Device Abstraction (`Devices` Module)
-   **`ACESDevice`**: References the `OpenColorIO` configuration (implied) or internal ACES transforms. It's a "Virtual Device" representing the Color Pipeline.
-   **`VirtualDevice`**: Base protocol for things that exist in the scene (Cameras, Lights).

## 5. Synthesis for MetaVisKit2

### Reuse Strategy
-   **Keep:** `Asset`, `NodeGraph`, `Project` data structures.
-   **Keep:** `ProjectMode` (Cinematic, Music Video, etc.).
-   **Keep:** `ACESDevice` concept (reformalized as `ColorPipeline`).

### New Architecture Required
1.  **`Logic/SessionManager`**: 
    -   Manages the `activeProject`.
    -   Handles file I/O (Save/Load).
    -   Manages the Undo/Redo stack (CommandBuffer pattern).
2.  **`Logic/AssetController`**:
    -   Orchestrates proxy generation.
    -   Manages the LRU cache for `AssetManager`.
3.  **`Logic/GraphExecutor`**:
    -   The *runtime* that actually executes the `NodeGraph` data.
    -   Mapping: `Node` data -> `Metal` kernel.
