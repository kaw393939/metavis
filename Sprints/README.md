# Sprints

Each subfolder is a single “feature sprint” plan.

Rules for these sprints:

- Test-driven with end-to-end validation.
- Prefer generated deterministic data over mocks.
  - Use procedural generators (SMPTE/macbeth/zone plate), timeline construction helpers, and real export/QC.
  - If an external dependency is unavoidable (network, hardware), isolate it behind an integration test that can be skipped via environment gates.
- Every sprint defines:
  - Goal + acceptance criteria
  - Existing code to change
  - New code to add
  - Tests to update/add (favor cross-module E2E tests)
  - Deterministic test data strategy

Notes:
- `12_creator_workflow_backlog` is planning-only: it captures product direction/backlog for later scheduling.
