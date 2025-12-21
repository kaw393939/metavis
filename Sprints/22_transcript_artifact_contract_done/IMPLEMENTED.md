# Implemented

## Summary
- Added a stable word-level transcript sidecar contract (`TranscriptArtifact`) with explicit `source*Ticks` + `timeline*Ticks` fields (ticks = 1/60000s).
- Added a deliverable sidecar kind + request (`.transcriptWordsJSON`) and a writer that can emit deterministic JSON from `CaptionCue` inputs.
- Wired sidecar writing into `ProjectSession.exportDeliverable(...)` so transcript artifacts are packaged and recorded in the manifest like other sidecars.

## Artifacts
- Deliverable sidecar file: `transcript_words.json` (default name; configurable per request)

## Tests
- `TranscriptSidecarContractE2ETests.test_export_deliverable_writes_transcript_words_json_sidecar`
- `TranscriptSidecarContractE2ETests.test_export_deliverable_transcript_words_json_uses_caption_discovery`

## Code pointers
- Contract model: `Sources/MetaVisCore/Transcript/TranscriptArtifact.swift`
- Sidecar kind/request: `Sources/MetaVisExport/Deliverables/DeliverableSidecar.swift`
- Writer: `Sources/MetaVisExport/Deliverables/SidecarWriters.swift` (`TranscriptSidecarWriter`)
- Integration point: `Sources/MetaVisSession/ProjectSession.swift` (deliverable sidecar switch)
