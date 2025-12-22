# Sprint 24c — Dependencies & Touchpoints

This sprint is contract-heavy and will touch multiple existing sprint outputs.

## Depends on
- Sprint 24a — Upgraded sensors (deterministic tracks, governed warnings)
- Sprint 24 — Speaker diarization artifacts + governed attribution sidecar

## Key code touchpoints (current repo)
- `Sources/MetaVisPerception/MasterSensorIngestor.swift` (sensor compiler)
- `Sources/MetaVisPerception/MasterSensors.swift` (schema v4)
- `Sources/MetaVisPerception/Models/SemanticFrame.swift` (LLM boundary — needs upgrade)
- `Sources/MetaVisPerception/Services/VisualContextAggregator.swift` (placeholder semantic synthesis)
- `Sources/MetaVisCore/Confidence/ConfidenceRecordV1.swift` (governed confidence primitives)
- `Sources/MetaVisLab/DiarizeCommand.swift` (speaker attribution + confidence sidecar)

## Implemented modules
- `Sources/MetaVisCore/Confidence/ConfidenceLevelV1.swift` (epistemic confidence level)
- `Sources/MetaVisCore/Provenance/ProvenanceRefV1.swift` (or extend `EvidenceRefV1`)
- `Sources/MetaVisPerception/Temporal/TemporalContextAggregator.swift`
- `Sources/MetaVisPerception/Temporal/TemporalContextV1.swift`
- `Sources/MetaVisPerception/Identity/IdentityBindingGraphV1.swift`
- `Sources/MetaVisPerception/Models/SemanticFrameV2.swift`

