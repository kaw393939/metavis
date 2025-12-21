# Implemented Features

## Status: Implemented (core contracts)

## Accomplishments
- Deterministic VFR fixture generation + detection via ffmpeg and `VideoTimingProbe`.
- VFR normalization policy decision layer (`VideoTimingNormalization`).
- Renderer time mapping for VFR sources (timeline time quantization in `ClipReader`).
- End-to-end export contract: exporting a timeline built from a VFR fixture produces a CFR-like deliverable (probe reports not VFR-likely).
- End-to-end sync contract: exported audio marker aligns with a deterministic visual transition, including after a trim-in style edit (via clip offset).

## Code pointers
- Probe: `Sources/MetaVisIngest/Timing/VideoTimingProbe.swift`
- Decision policy: `Sources/MetaVisIngest/Timing/VideoTimingNormalization.swift`
- Application (timeline time quantization): `Sources/MetaVisSimulation/ClipReader.swift`
- Export trace visibility: `Sources/MetaVisSession/ProjectSession.swift` (`traceVFRDecisionsIfNeeded`)

## Test pointers
- Fixture generation + detection: `Tests/MetaVisIngestTests/VFRGeneratedFixtureTests.swift`
- Export normalization E2E: `Tests/MetaVisExportTests/VFRNormalizationExportE2ETests.swift`
- Sync marker E2E (baseline + trim-in): `Tests/MetaVisExportTests/VFRSyncContractE2ETests.swift`
- Quantization unit tests: `Tests/MetaVisSimulationTests/VFRTimingQuantizationTests.swift`
