# Sprint 03 — TDD Plan (Policy Bundles)

## Tests (write first)

### 1) `PolicyBundleE2ETests.test_policy_bundle_drives_qc()`
- Location: `Tests/MetaVisSessionTests/PolicyBundleE2ETests.swift`
- Steps:
  - Create session with license requiring watermark.
  - Export 1–2 seconds.
  - Build policy bundle from session.
  - Run deterministic QC using bundle requirements.
  - Assert pass.

### 2) `PolicyBundleTests.test_bundle_includes_export_governance()`
- Asserts the bundle’s export portion matches `UserPlan` + `ProjectLicense`.

### 3) `AIGateIntegrationTests.test_gemini_gate_optional()`
- Integration test that runs only if `GEMINI_API_KEY` exists; otherwise asserts “skipped”.

### 4) `PrivacyPolicyTests.test_defaults_disallow_raw_media_upload()`
- Deterministic unit test.
- Assert default policy is local-first and does not allow raw media upload without explicit opt-in.

## Production steps
1. Add `QualityPolicyBundle` (name TBD) in `MetaVisCore`.
2. Update session to compute it.
3. Update QC APIs to accept it (or a `DeterministicQCPolicy`).

## Definition of done
- Deterministic policy-driven QC is enforceable end-to-end without mocks.
