# Sprint 03 — Quality Governance as Policy Bundles

## Goal
Unify export constraints, QC requirements, AI-gate requirements, and privacy/upload permissions into an explicit policy bundle computed by session and enforced consistently.

## Acceptance criteria
- A single “policy bundle” type exists that includes:
  - export constraints (existing `ExportGovernance`)
  - deterministic QC requirements (e.g. require audio track, non-silence threshold, fps tolerance)
  - optional AI gate requirements (prompt template + required signals)
  - privacy/upload permissions (default: no raw media upload; deliverables-only opt-in)
- `ProjectSession.exportMovie(...)` computes and passes the bundle end-to-end.
- QC can be invoked using the bundle and validates outputs deterministically.
- E2E test: recipe/session export → QC uses bundle requirements.

## Existing code likely touched
- `Sources/MetaVisExport/ExportGovernance.swift`
- `Sources/MetaVisSession/ProjectSession.swift`
- `Sources/MetaVisQC/VideoQC.swift`, `GeminiQC.swift`
- `Sources/MetaVisCore/GovernanceTypes.swift`

## New code to add
- `Sources/MetaVisCore/GovernancePolicy.swift` (or `QualityPolicyBundle.swift`)
  - `export: ExportGovernance`
  - `qc: DeterministicQCPolicy`
  - `ai: AIGatePolicy?`
  - `privacy: PrivacyPolicy`

## Alignment note
This bundle is the control plane for local-first creator workflows: it should be able to express “what leaves the machine” (if anything), and what deliverables/sidecars (captions) are required.

## Test strategy (no mocks)
- E2E export to file.
- QC reads file and validates based on policy.
- AI gate tests are integration-gated by env var; deterministic core must always run.
