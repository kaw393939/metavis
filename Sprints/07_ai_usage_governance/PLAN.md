# Sprint 07 — AI Usage Governance (Prompt + Privacy Policy)

## Goal
Formalize AI usage with explicit governance: what data is sent (if any), prompt structure, opt-in/out policy, and privacy-first defaults (local-first).

Reference: `Docs/research_notes/legacy_autopsy_coreml_vision.md` (determinism + metadata capture stance)

## Acceptance criteria
- A typed AI usage policy exists (what can be sent, redaction rules, allowed models).
- Gemini gate uses a structured prompt builder that includes deterministic metrics.
- The system can run deterministically without Gemini (skip behavior remains).
- Integration test runs Gemini only when env var is present.
 - Default posture is “no raw media leaves the machine”; any cloud AI usage is explicit and policy-driven.
 - Any AI/ML output recorded in QC/traces includes model identifier/version and configuration inputs (even when the result is validated with tolerant metrics).

## Existing code likely touched
- `Sources/MetaVisQC/GeminiQC.swift`
- `Sources/MetaVisServices/Gemini/*`
- `Sources/MetaVisSession/ProjectSession.swift` (if policy is session-driven)

## New code to add
- `Sources/MetaVisCore/AIGovernance.swift` (policy types)
- `Sources/MetaVisQC/GeminiPromptBuilder.swift`

## Existing tests to update
- Any tests relying on raw prompt strings.

## Test strategy
- Deterministic unit tests for prompt builder (no network).
- Integration-gated test for Gemini call path.
