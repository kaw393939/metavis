# Concept — Vibe Editing (Human-Directed AI Video Editing)

## North Star
Build a system where a human can direct edits in natural language (“vibe coding for video”), while the system executes **deterministic, reversible, test-locked editing primitives**.

The human is the director.
The AI is a fast assistant.
The editor core must remain reliable, explainable, and undoable.

## Core Contract (End-to-End)
1) **Human intent**: Free-form instruction (e.g. “tighten this”, “move macbeth earlier”, “ripple trim out by 0.5s”).
2) **Grounded context**: The model receives a stable, small JSON context describing the current timeline (clip IDs, names, track kind, start/duration/offset).
3) **Typed intent**: The model emits a `UserIntent` (structured JSON) that includes:
   - `action`
   - `params`
   - deterministic `clipId` targeting when applicable
4) **Typed commands**: `UserIntent` maps to one or more `IntentCommand`s.
5) **Deterministic execution**: `CommandExecutor` applies the commands to a `Timeline`.
6) **Reversibility**: Each applied edit participates in undo/redo.
7) **Verification**: Tests and trace events prove stability and guard against regressions.

## Design Principles
- **Determinism over cleverness**: same inputs must produce same outputs.
- **Explainability**: always be able to answer “what changed?”
- **Reversibility**: every edit must be undoable.
- **Minimal primitive set**: the AI composes edits from a small set of well-defined operations.
- **Separation of concerns**:
  - interpretation can be fuzzy,
  - execution cannot be.

## Editing Semantics (Must Be Explicit)
Editing commands must define (and tests must lock):
- **Targeting**: which clip/track(s) are affected.
- **Absolute vs delta**:
  - “to 3.25s” means set an absolute value.
  - “by 0.5s” means apply a delta (direction must be defined).
- **Ripple behavior**:
  - non-ripple edits do not move downstream clips.
  - ripple edits shift downstream clips deterministically.
- **Overlap/collision policy**: moving clips must have a documented and tested rule.
- **Transition interactions**: trims/blades/deletes must define what happens to transitions.

Chosen defaults (Sprint 19):
- Overlaps are allowed (no auto-ripple), but the system emits a deterministic warning trace when overlap exists after placement.
- Ripple edits apply to the target track only (until a first-class link/group model exists).
- “to X” is absolute; “by X” is delta.

## Minimal Tools / Primitives (Editor Core)
The editor core should provide a small set of primitives that cover most early workflows:
- Move
- Trim end
- Trim in (slip)
- Blade/cut
- Ripple trim out
- Ripple trim in
- Ripple delete
- Retime (as an effect)

## What “Done” Means for Editing
Editing is “done enough to move on” when:
- The semantics are documented and test-locked.
- Deterministic targeting works end-to-end.
- Undo/redo works for all edit intents.
- The system has a clear overlap policy and clear multi-track rules.
- A small suite of end-to-end tests covers:
  - ordinal targeting ("second clip")
  - name targeting ("macbeth")
  - clipId targeting
  - numeric parsing (absolute + delta)
  - transitions edge cases

## Non-Goals
- Full creative autonomy.
- “Best guess” edits without evidence or without reversible primitives.
- Expanding the editor core indefinitely; new features should prefer composition.
