# Sprint 04: Heuristic Externalization

## 1. Objective
Decouple quality control logic from code. Move hardcoded "magic numbers" (silence thresholds, black level tolerance, scene change sensitivity) from `MetaVisQC` and `MetaVisPerception` into a versioned `GovernanceProfile` JSON schema.

## 2. Scope
*   **Target Modules**: `MetaVisQC`, `MetaVisPerception`, `MetaVisCore`
*   **Key Files**: `VideoQC.swift`, `VideoContentQC.swift`, `QualityPolicyBundle.swift`

## 3. Acceptance Criteria
1.  **Configurability**: Changing a threshold in `default_policy.json` immediately changes QC pass/fail results without recompilation.
2.  **Profiles**: Support multiple named profiles (e.g., "BroadcastSafe", "WebSocial", "RoughCut").
3.  **Validation**: A generic `GovernanceEngine` applies checks based on the loaded profile.

## 4. Implementation Strategy
*   Define `GovernanceProfile` struct (Codable).
*   Refactor `VideoContentQC` to accept `GovernanceProfile` in `init`.
*   Load `Sources/MetaVisCore/Resources/policy_defaults.json` at runtime.

## 5. Artifacts
*   [Data Dictionary](./data_dictionary.md)
*   [TDD Plan](./tdd_plan.md)
