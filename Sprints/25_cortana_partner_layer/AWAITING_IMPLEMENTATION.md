# Awaiting Implementation

## Gaps / Work Items

### 1) Cast List (project memory)
- Add a project-level structure (e.g. `CastList`) that maps:
  - `personId` (stable, machine) → `displayName` (human)
- Persist it in the project document (alongside `ProjectState`).
- Tests:
  - round-trip save/load
  - deterministic JSON output

### 2) Identity wiring
- Decide how `personId` is produced for downstream systems:
  - keep current per-run tracking IDs for sensors, but optionally add a stable re-id layer (Sprint 18 face hashing) that can promote/merge identities.
- Tests:
  - deterministic identity assignment on synthetic fixtures
  - stable mapping when re-loading a project

### 3) Agent API surface
- Define typed actions (example shape):
  - `AgentAction.removeSilence(...)`
  - `AgentAction.colorGrade(person:displayName, ...)`
- The API should:
  - compile to deterministic, typed commands
  - emit traces / audit artifacts

### 4) One end-to-end “partner” workflow
- Pick a single workflow that is clearly reviewable and testable:
  - propose → evidence → bounded edits → artifacts
- Prefer running locally and deterministically; gate any network QA behind env vars.
