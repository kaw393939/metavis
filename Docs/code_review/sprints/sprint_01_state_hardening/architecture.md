# Architecture: State Management Hardening

## Current State (Problem)
`ProjectSession` holds a `ProjectState` struct.
`ProjectState` holds a `Timeline` struct.
`Timeline` holds `[Track]` arrays.

When `Undo` is pushed:

```swift
history.append(currentState) // Deep copy of the entire value tree
```

This causes massive memory duplication.

## Current State (Now Implemented)

`ProjectSession` stores undo/redo history as *compact steps* rather than whole-state snapshots for simple UI edits.

```swift
struct UndoStep {
    let undo: (inout ProjectState) -> Void
    let redo: (inout ProjectState) -> Void
}

// dispatch(EditAction): push an UndoStep, not a ProjectState
```

This changes the memory growth curve for common edits: history grows with the number of edits, not with the size of the timeline tree.

Important: intent/command execution still uses snapshot-style undo steps (by capturing before/after) until we implement explicit inverses at the command layer.

## Proposed Next Layer (Optional): Structural sharing inside `Timeline`
If profiling shows Timeline mutations are still costly due to nested array copies, add structural sharing inside the timeline model.

### Option A: CoW box for hot collections

Introduce a final, non-ObjC storage box and use `isKnownUniquelyReferenced(&storage)` to implement CoW around `tracks` and/or `clips`.

### Option B: Persistent vector / chunked B-tree

Use a persistent sequence (bit-mapped vector trie, branching ~32) with path-copying, plus a transient builder for batch operations.
This is the “maximum scalability” option when timelines become very large and snapshotting needs to remain cheap.

### `CowBox<T>`
A generic reference-counted box that only copies the underlying value `T` upon mutation if the reference count > 1.

```swift
struct Timeline {
    // Before: var tracks: [Track]
    // After:  var tracks: CowBox<[Track]> 
}
```

This ensures that pushing `Timeline` to the history stack only copies the *pointer* to the box. The underlying `[Track]` array is shared until a specific track list is modified.

## Modules Affected
*   **MetaVisCore**: Add `CowBox<T>`.
*   **MetaVisTimeline**: Update `Timeline` to use `CowBox`.
*   **MetaVisSession**: No changes needed to `history` logic itself; the benefit is automatic.
