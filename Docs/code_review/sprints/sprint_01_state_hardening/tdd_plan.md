# TDD Plan: Sprint 01

## Existing Tests
*   `MetaVisSessionTests/UndoRedoTests.swift`: Validates logic correctness.

Note: in this repo, undo/redo behavior is also covered by:
* `MetaVisSessionTests/ProjectSessionTests.swift`
* `MetaVisSessionTests/IntentUndoRedoTests.swift`
* `MetaVisSessionTests/BatchedCommandUndoRedoE2ETests.swift`

## New Tests
1.  **UndoStep correctness for dispatch actions**:
    *   Add/remove track/clip and set project name.
    *   Undo/redo repeatedly.
    *   **Assert**: timeline/config return to the exact expected state every time.

2.  **Performance benchmark (Release)**:
    *   Use XCTest `measure` (or a small benchmark harness) to measure:
        * `dispatch(.addClip)` / `dispatch(.removeClip)` on a timeline with 1,000 clips
        * `undo()` / `redo()` for those actions
    *   Track p50/p95 runtime across changes.

3.  **Memory measurement (Instruments)**:
    *   Use Allocations + VM Tracker on a scriptable scenario:
        * Create a timeline with 10,000 clips.
        * Perform 100 simple edits that hit `dispatch(EditAction)`.
        * Undo/redo them.
    *   **Assert (by observation/recorded evidence)**: memory growth is bounded and does not scale with the full timeline size per edit.

## Test Command

```bash
swift test --filter MetaVisSessionTests
```
