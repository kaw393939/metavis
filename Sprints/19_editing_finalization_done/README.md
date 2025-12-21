# Sprint 19 — Editing Finalization (Vibe Editing Core)

## Goal
Finish the “vibe editing” editor core so we can stop changing editing semantics and move on to higher-level workflows.

In Sprint 19, “done” means:
- Editing semantics are explicit and stable.
- Natural-language requests map to deterministic, typed edits.
- Every edit is reversible (undo/redo) and observable (traces).
- The behavior is locked by tests so future work doesn’t re-break editing.

## Why This Sprint Exists
Sprint 18 delivered the critical editing primitives and deterministic targeting.
Sprint 19 closes the remaining gaps that prevent confidently treating editing as a finished subsystem:
- delta vs absolute semantics across operations
- overlap/collision policy
- transition-aware trimming/deleting
- multi-track rules (video + audio) and targeting
- robust parameter parsing (seconds/timecode/frames)
- multi-command requests (“do X then Y”) and deterministic batching

## Current Baseline (Already In Place)
- Deterministic targeting via `LLMEditingContext` + `clipId` support.
- Typed commands: move, trim end, trim in, blade/cut, ripple trim out/in, ripple delete, retime.
- Procedural sources respect clip-local time.
- End-to-end tests for name/ordinal targeting and numeric parsing.

## Scope
### In scope
1) **Semantics finalization (policy + tests)**
2) **Overlap/collision policy**
3) **Transition-aware edit behavior**
4) **Multi-track rules and track targeting**
5) **Robust parameter parsing and unit support**
6) **Deterministic command batching + trace coverage**

### Out of scope
- Full FCP parity beyond what is required to stabilize the core (e.g., advanced roll/slide tooling across many clips).
- Fully autonomous editing without human direction.

## Required Decisions (must be made early)
These are product rules that must be encoded into deterministic behavior:
### Decision Log (Sprint 19)
1) **Overlap policy** (move/placement collisions)
  - **Chosen**: allow overlaps (permissive), no auto-ripple.
  - **Requirement**: emit a deterministic warning trace when overlap exists after placement.

2) **Multi-track ripple scope**
  - **Chosen**: ripple only within the target track.
  - Rationale: no implicit audio linking until a first-class link/group model exists.

3) **Delta language rules**
  - **Chosen**:
    - “to X” = absolute set
    - “by X” = apply delta
  - Ripple trim out:
    - “by X” = shorten by default
    - “extend by X” / “longer by X” / “add X” = lengthen
  - Move:
    - “by -X” = earlier, “by +X” = later
    - “earlier by X” / “later by X” are also supported.

## Work Items
### 1) Semantics spec (single source of truth)
- Write a short semantics spec describing each command:
  - inputs
  - absolute vs delta forms
  - ripple behavior
  - transition behavior
  - edge cases (clamps/guards)
- Add a “Decision Log” section capturing the 3 decisions above.

### 2) Overlap/collision policy implementation + tests
- Implement the chosen overlap policy in `CommandExecutor.moveClip` (and any other operation that can create overlap).
- Add tests that prove the policy on:
  - moving a clip into another clip’s time
  - moving a clip before time 0
  - moving a clip across multiple clips

### 3) Transition-aware trimming/deleting
- Define and implement rules for:
  - trimming into/out of transitions
  - ripple delete on clips with transitionIn/transitionOut
  - blade with transitions (already partially covered; extend to adjacent clips)
- Add tests covering transition edge cases.

### 4) Multi-track targeting + ripple rules
- Extend targeting so an intent can specify:
  - track kind (video/audio)
  - track name or index (deterministic)
- Implement (based on decision) ripple behaviors across tracks.
- Add tests for:
  - ripple operations in a multi-track timeline
  - video+audio linked behavior if selected

### 5) Robust parameter parsing (still deterministic)
- Add parsing support for:
  - timecode strings (e.g. `00:00:04.12`)
  - frame-based expressions (e.g. `12f` at 24fps)
  - milliseconds (`500ms`)
  - multiple numbers in one prompt when batching is requested
- Ensure parsing failures are safe and observable (trace + no-op).

### 6) Deterministic batching
- Allow a single request to emit multiple commands in stable order.
- Add tests for:
  - “move macbeth to 1s then ripple trim out by 0.5s”
  - ordering stability
  - undo/redo of multi-command sequences

## Test Plan (Definition of Done)
Sprint 19 is complete when all are true:
- A focused E2E suite covers:
  - targeting: clipId + ordinal + name + (track selection if implemented)
  - numeric parsing: absolute + delta + timecode/frames
  - overlap policy cases
  - transition edge cases
  - multi-track ripple cases
  - batching (multi-command) + undo/redo
- Editor semantics spec exists and matches behavior.
- No remaining TODOs in the editing core that change semantics.

## Deliverables
- Semantics spec document
- Updated executor semantics (as required)
- A test suite that acts as the “contract” for editing
