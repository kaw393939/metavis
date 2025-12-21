# Sprint 07 — TDD Plan (AI Usage Governance)

## Tests (write first)

### 0) `AIGovernanceTests.test_default_policy_is_local_only()`
- Deterministic unit test.
- Asserts default policy does not permit sending raw media off-device.

### 1) `GeminiPromptBuilderTests.test_prompt_includes_required_metrics()`
- Location: `Tests/MetaVisQCTests/GeminiPromptBuilderTests.swift` (or nearest QC tests)
- Asserts prompt includes: duration/fps/resolution + expected pattern text.

### 1b) `GeminiPromptBuilderTests.test_prompt_includes_model_and_policy_metadata_when_enabled()`
- Asserts prompt (or attached structured payload) includes: model name/version, policy mode, and redaction summary.

### 2) `AIGovernanceTests.test_policy_redacts_paths_and_ids()`
- Ensures redaction is deterministic.

### 3) `GeminiGateIntegrationTests.test_gate_skips_without_api_key()`
- Asserts deterministic skip verdict.

### 4) `GeminiGateIntegrationTests.test_gate_runs_with_api_key()`
- Runs only when env var exists.

## Production steps
1. Add AI governance types.
2. Add prompt builder used by `GeminiQC`.
3. Ensure gate behavior is policy-driven and remains optional.

## Definition of done
- Prompt governance is enforceable and test-covered without mocks.
