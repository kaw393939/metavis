# MetaVisSession Assessment

## Initial Assessment
MetaVisSession is the central nervous system ("Brain") of the application. It manages the `ProjectState`, orchestrates the `ProjectSession` actor, handles Undo/Redo, and ties together Perception (Eyes), Intelligence (LLM), and Export (Output).

## Capabilities

### 1. The Brain (`ProjectSession`)
- **Action Dispatch**: Central `dispatch(_ action: EditAction)` method for mutating state, ensuring thread safety via MainActor/Actor isolation.
- **Undo/Redo**: Implements a snapshot-based undo stack (`[ProjectState]`).
- **Integration**:
    - **Perception**: Calls `VisualContextAggregator` to update `state.visualContext`.
    - **Intelligence**: Uses `LocalLLMService` to process natural language intents (`processCommand`).
    - **Export**: Orchestrates the export process, generating `DeliverableManifest` and running QC.

### 2. God Test Reference
- **`GodTestBuilder`**: A factory for a "Golden Master" timeline used for calibration.
- **Content**: Includes SMPTE Bars, Macbeth Charts, Zone Plates, and audio test tones (Sine, Sweep, Impulse). Essential for pipeline verification.

### 3. Deliverable Orchestration
- **Policy Enforcement**: Builds `QualityPolicyBundle` to enforce licensing (watermarks) and QC rules.
- **Manifest Generation**: orchestrates the writing of the complex Deliverable Bundle (Video + Sidecars + QC Reports).
- **Sidecars**: Handles standard sidecars like Captions (VTT/SRT) and Thumbnails/Contact Sheets.

## Technical Gaps & Debt

### 1. Naive State Management
- **Issue**: The Undo stack stores full copies of `ProjectState`.
- **Debt**: O(N) memory usage where N is history depth. For large projects (many clips), this will explode memory usage quickly.
- **Fix**: Needs a structural sharing data structure (Persistent Data Structure) or diff-based history.

### 2. Extensibility Limit
- **Issue**: `EditAction` is a hardcoded enum (`addTrack`, `addClip`, etc.).
- **Debt**: Adding new editing operations requires modifying the core `ProjectSession` file. No plugin architecture for new tools.

### 3. Concurrency
- **Issue**: `ProjectSession` is a single actor. Heavy operations (like analyzing a frame or serializing large JSON contexts for LLM) run on this actor, potentially blocking UI responsiveness during "thinking" time.

## Improvements

1.  **State Optimization**: Implement a "Copy-on-Write" or "Persistent" timeline structure to make snapshots cheap.
2.  **Command Pattern**: Refactor `EditAction` into an open protocol `Command` so new edits can be defined in other modules.
3.  **Background Intelligence**: Offload LLM context building and Perception analysis to a background isolation context to keep the `ProjectSession` actor free for high-frequency UI updates.
