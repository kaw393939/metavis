# Test Architecture Research & Sprint Mapping

## Overview
This document maps the historical Sprints (01-35) to the existing Test Suites. It identifies coverage gaps and opportunities to expose capabilities via a "Control Plane".

## Sprint to Test Mapping

### Sprint 01: Project Recipes
*   **Goal:** JSON-defined project structure.
*   **Tests:** `MetaVisExportTests/RecipeE2ETests.swift`

### Sprint 02: Render Devices (Streaming Pipeline)
*   **Goal:** Abstract rendering backend.
*   **Tests:** `MetaVisExportTests/RenderDeviceE2ETests.swift`
*   **Control Plane Capability:** `VirtualDevice` (MetaVisCore).

### Sprint 03: Policy Bundles
*   **Goal:** Governance and configuration limits.
*   **Tests:** 
    *   `MetaVisCoreTests/PolicyLibraryTests.swift`
    *   `MetaVisCoreTests/PrivacyPolicyTests.swift`

### Sprint 04: Feature Multipass
*   **Goal:** Multi-pass rendering support.
*   **Tests:** (Likely covered in `VideoExportTests.swift` or `RenderGraphTests` - Need to verify).

### Sprint 06: QC Expansion
*   **Goal:** Automated Quality Control checks.
*   **Tests:** `MetaVisExportTests/QCExpansionE2ETests.swift`

### Sprint 07: AI Usage Governance
*   **Goal:** Gate AI features based on privacy/ethics.
*   **Tests:** 
    *   `MetaVisCoreTests/AIGovernanceTests.swift`
    *   `MetaVisExportTests/AIGateIntegrationTests.swift`

### Sprint 09: Audio Hardening
*   **Goal:** Robust audio pipeline.
*   **Tests:** 
    *   `MetaVisAudioTests/AudioGraphTests.swift`
    *   `MetaVisExportTests/AudioNonSilenceExportTests.swift`

### Sprint 14: Transitions (Dip/Wipe)
*   **Goal:** Standard dissolve and wipe transitions.
*   **Tests:** `MetaVisExportTests/TransitionDipWipeE2ETests.swift`

### Sprint 21: VFR Normalization
*   **Goal:** Handle Variable Frame Rate video.
*   **Tests:** 
    *   `MetaVisExportTests/VFRNormalizationExportE2ETests.swift`
    *   `MetaVisIngestTests/VideoTimingNormalizationTests.swift`

### Sprint 22: Transcript Artifact Contract
*   **Goal:** Stable transcript JSONL format.
*   **Tests:** `MetaVisExportTests/TranscriptSidecarContractE2ETests.swift`

## Gap Analysis (Sprints with weak explicit mapping)
*   **Sprint 23 (Whisper CLI):** Covered by `MetaVisLabTests`?
*   **Sprint 24 (Diarization):** Found `DiarizeCommandContractTests.swift` in `MetaVisLabTests`.

## Control Plane Discovery
The following "Registries" and "Factries" detected in tests could form the Control Plane:
1.  **`PolicyLibrary`**: Enumerable policies.
2.  **`VirtualDevice`**: Enumerable render capabilities.
3.  **`Recipe`**: Enumerable project templates.
4.  **`Transition`**: (Inferred) registry of effect types.
