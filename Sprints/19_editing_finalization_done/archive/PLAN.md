# Sprint 19 — Editing Finalization (Plan)

## Goal
Make editing a “finished subsystem” suitable for human-directed AI editing.

Practically:
- semantics become stable
- regressions become unlikely
- higher-level workflows (auto enhance, creator flows, QC) can assume editing is correct

## Definition of Done
- A semantics spec exists and matches implementation.
- The 3 policy decisions are made and encoded as tests.
- E2E coverage exists for:
  - targeting (clipId/ordinal/name + optional track selection)
  - numeric parsing (absolute/delta + timecode/frames)
  - overlap policy
  - transitions
  - multi-track ripple
  - batching + undo/redo

## Required Decisions (Blockers)
1) Overlap policy for move/placement
2) Multi-track ripple scope
3) Delta language rules (“by”, “extend by”, “shorten by”)

## Work Breakdown
### A) Semantics Spec + Decision Log
- Create a short document: one table per command with:
  - inputs
  - absolute vs delta forms
  - ripple behavior
  - transition behavior
  - clamping rules
- Add a Decision Log section with the three decisions.

### B) Overlap Policy
- Implement chosen policy in executor.
- Add tests for overlap/collision scenarios.

### C) Transition-Aware Edits
- Define behavior for trims/blades/deletes with transitions.
- Add tests for transition edge cases.

### D) Multi-Track Editing Rules
- Add deterministic track selection mechanism.
- Implement ripple scope per decision.
- Add tests for multi-track timelines.

### E) Robust Parsing
- Support timecode (`HH:MM:SS(.sss)`), frames, milliseconds.
- Make parsing deterministic and failure-safe.
- Add parsing tests.

### F) Deterministic Batching + Undo/Redo
- Support multi-command intent emission and stable ordering.
- Ensure undo/redo applies the whole batch as one reversible operation.
- Add E2E tests.

## Notes
- Prefer tests-first changes to lock semantics.
- Do not expand the primitive set unless necessary to close semantic gaps.
