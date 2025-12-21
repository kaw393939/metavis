# Sprint 31: The Collaborative Core (CRDT)

## Goal
Enable real-time, race-free collaboration between the Human User and the AI Agents (Gemini/LIGM) by wrapping the `Timeline` data model in a Conflict-Free Replicated Data Type (CRDT).

## Rationale
Currently, the `ProjectSession` guards state with an actor. However, if the AI takes 5 seconds to "think" about a color grade, and the user deletes a clip in the meantime, the AI's eventual command ("Color scale for Clip X") will fail or corrupt the state. A CRDT ensures valid merge semantics.

## Deliverables
1.  **`TimelineCRDT`:** A wrapper around the `Timeline` struct that manages a set of operations (OpLog).
2.  **Operation Definitions:** `AddClipOp`, `RemoveClipOp`, `ModifyEffectOp`.
3.  **Refactored `CommandExecutor`:** The executor currently mutates `Timeline` directly. It must be refactored to emit *Operations* to the CRDT.
4.  **"Ghost User" Test:** A test harnessed running two concurrent "users" (threads) making conflicting edits, verifying the final state converges deterministically.

## Out of Scope
- Network replication (P2P syncing). This sprint is strictly for *local* collaboration between Actor Isolation Contexts (Human vs AI).

## Optimization: Apple Silicon Concurrency
*   **OSAllocatedUnfairLock:** Use this low-level lock (available in macOS 16) for protecting the CRDT OpLog if high contention is observed between the Render Thread and the AI Agent.
