# Sprint 01: State Management Hardening

## 1. Objective
Refactor `ProjectSession` and `ProjectState` to use **Structural Sharing** (Copy-On-Write) for the Undo/Redo stack. Currently, every edit copies the entire `Timeline` value tree, leading to O(N) memory growth where N is the number of edit steps * timeline size.

**Status (implemented in code)**: `dispatch(EditAction)` now records compact undo steps (inverse operations) instead of storing full `ProjectState` snapshots per edit. This eliminates coarse O(N) snapshot growth for interactive edits while preserving existing intent/batched-command undo behavior.

## 2. Scope
*   **Target Modules**: `MetaVisSession`, `MetaVisTimeline`
*   **Key Files**: `ProjectSession.swift`, `ProjectState.swift`, `Timeline.swift`

## 3. Acceptance Criteria
1.  **No full snapshots for simple edits**: `dispatch(EditAction)` must not store whole `ProjectState` values in undo/redo history.
2.  **Undo/Redo correctness**: Existing undo/redo tests continue to pass, and `dispatch` actions undo/redo deterministically.
3.  **Performance**: For a timeline with 1,000 clips, `dispatch` and `undo/redo` operations remain sub-frame in Release builds (measure p50/p95; do not regress materially).
4.  **Memory behavior**: Undo stack depth for simple edits grows roughly with *edit count*, not with *timeline size* (validated via Instruments Allocations/VM Tracker and/or a scripted benchmark).

Notes:
* We keep snapshot-based undo for intent/command execution until we introduce explicit inverses for those command types.
* This sprint is about minimizing unnecessary copying and making future structural sharing straightforward, not forcing a single data structure choice prematurely.

## 4. Implementation Strategy
We implement the highest leverage changes first, then move “deeper” only if profiling shows it’s needed.

### Phase A (done): Delta-based undo for discrete UI edits
* Replace `undoStack: [ProjectState]` / `redoStack: [ProjectState]` with stacks of compact undo steps.
* Each `UndoStep` stores `undo(inout ProjectState)` and `redo(inout ProjectState)` closures for `EditAction`.
* This avoids retaining whole historical `ProjectState` snapshots for trivial edits.

### Phase B (next, if needed): Structural sharing inside Timeline collections
If Timeline mutations still cause large copies (e.g., due to nested `[Track]` / `[Clip]` copies on mutation), adopt one of these Swift 2025 patterns:

1. **CoW storage box for hot collections**
    * Make leaf storage a final, non-ObjC class and use `isKnownUniquelyReferenced(&storage)` to implement CoW.
    * Prefer `ContiguousArray`/`Array` for leaf buffers where possible; use `ManagedBuffer` only when you need header + tail allocation.

2. **Persistent vector / chunked B-tree for large sequences**
    * For truly large timelines, use a persistent vector/trie (branch factor ~32) with path-copying, or a chunked B-tree.
    * Provide a transient/builder type for batch edits (amortizes allocations), then seal back to an immutable value.

3. **Avoid common CoW footguns**
    * Avoid long-lived slices/aliases to arrays that are later mutated.
    * For hot loops, use buffer-pointer APIs to avoid per-element CoW checks.

## 5. Artifacts
*   [Architecture](./architecture.md)
*   [Data Dictionary](./data_dictionary.md)
*   [TDD Plan](./tdd_plan.md)

## 6. Completion Checklist (for `_done` rename)
* ✅ `dispatch(EditAction)` uses delta-based undo steps (no full-state snapshots per edit).
* ✅ Undo/redo correctness validated by existing tests.
* ⏳ Release perf numbers recorded (p50/p95) for dispatch + undo/redo on a 1,000-clip timeline.
* ⏳ Instruments evidence captured showing bounded memory growth for 10,000 clips + 100 edits.
