# Sprint 16 — TDD Plan (Feedback Loop)

## Tests (write first)

### 1) `EvidencePackSelectionTests.test_budgeted_selection_is_stable()`
- Build a small synthetic `MasterSensors` fixture (or reuse deterministic ingest output).
- Call `EvidencePackSelector.select(...)` twice with the same `seed`.
- Assert:
  - same timestamps
  - same ordering
  - never exceeds budgets

### 1b) `EvidencePackSelectionTests.test_selection_changes_with_seed()`
- Call selection with two different seeds.
- Assert the pack differs but still respects budgets.

### 2) `FeedbackLoopTests.test_qaloop_off_is_deterministic()`
- Run the orchestrator with `qa=off` twice.
- Assert the proposed outputs (recipes/commands) are byte-for-byte equal.

### 3) `FeedbackLoopTests.test_local_text_engine_runs_without_media()`
- Use `qa=local-text`.
- Ensure no media extraction is required.
- Assert it produces a structured `AcceptanceReport`.

### 3b) `FeedbackLoopTests.test_whitelist_enforcement_rejects_out_of_bounds_edits()`
- Provide a `ParameterWhitelist` and a QA engine stub that suggests edits outside bounds.
- Assert the edit applier clamps/rejects and records a violation.

### 4) `FeedbackLoopTests.test_async_parallelism_does_not_change_results()`
- Run with `maxConcurrency=1` and `maxConcurrency=2`.
- Assert the selected evidence pack and proposal outputs are identical (QA off or local-text).

### 5) `FeedbackLoopTests.test_escalation_adds_targeted_evidence_only()`
- Configure small budgets and a QA engine stub that requests escalation at specific timestamps.
- Assert the next cycle only adds the requested evidence (or a bounded superset) and stays within budgets.

## Production steps
1. Add `EvidencePack` model (manifest/assets/textSummary) and `EvidencePackBudget`.
2. Add deterministic `EvidencePackSelector` driven by sensors/descriptors + optional `seed`.
3. Add `AcceptanceReport` model + `ParameterWhitelist` enforcement in edit applier.
4. Add `QAEngine` protocol + `LocalTextQAEngine`.
5. Add `FeedbackLoopRunner` that supports N cycles + escalation ladder.
6. Add bounded-concurrency runner (task group + semaphore).

## Definition of done
- All tests pass.
- QA off produces deterministic outputs.
- Evidence selection respects budgets.
- Command shows progress and never appears “stuck.”
- Whitelist enforcement prevents unsafe edits.
- Escalation is targeted and budgeted.
