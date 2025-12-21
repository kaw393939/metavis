# Implemented (Sprint 24: Diarization Backbone)

## Status Update (2025-12-21)
Sprint 24’s diarization backbone is implemented:
- **ECAPA‑TDNN (CoreML)** speaker embeddings + clustering as the primary identity signal (when enabled)
- **Sticky Fusion** heuristic as a deterministic fallback

This document describes what is implemented and what artifacts/tests form the stable contract.

## Summary
- Produces speaker-labeled transcript words by assigning speaker IDs to word-level timings.
- Emits stable sidecars: speaker-tagged captions + a speaker map.
- Supports both:
	- baseline Sticky Fusion (face-dominance + hysteresis)
	- embedding-backed diarization (ECAPA‑TDNN)

Note: Future work is about tighter acceptance fixtures and higher-level Scene State summaries (safety ratings, speaker↔face binding confidence), not replacing the core diarization contract.

## Mandate Alignment (Next Upgrades)
The diarization backbone exists; the mandate requires we elevate it to **world-class, edit-grade** outputs by adding:
- **Cluster lifecycle** (born/lastActive/confidence/mergeCandidates/frozen) with deterministic, explainable merges.
- **First-class `OFFSCREEN`** semantics with contiguous spans and explicit emission on binding failure/decay.
- **Governed confidence surfaces** at the word level using a shared `MetaVisCore` confidence record (conceptually `ConfidenceRecord.v1`) with discrete grades + finite reason codes.
- **Identity Timeline artifact** (`identity.timeline.v1.json`) as the canonical spine for identity + fusion + confidence (cluster + binding + attribution).

These upgrades strengthen trust and downstream safety/QC, while keeping the existing artifacts stable and versioned.

## Artifacts
- `<out>/transcript.words.v1.jsonl` (speakerId/speakerLabel populated)
- `<out>/captions.vtt` (WebVTT with `<v Speaker>` voice tags)
- `<out>/speaker_map.v1.json` (stable mapping of speakerId → speakerLabel)

Planned internal artifact:
- `<out>/identity.timeline.v1.json` (cluster lifecycle, bindings, `OFFSCREEN`, governed confidence records, finite reason codes)

## Tests
- `SpeakerDiarizerContractTests` (MetaVisPerception)
- `DiarizeCommandContractTests` (MetaVisLab)

## Where it lives
- Core diarization engine: `Sources/MetaVisPerception/Diarization/...`
- CLI entrypoint: `Sources/MetaVisLab/DiarizeCommand.swift`
- Transcript record contract: `Sources/MetaVisCore/Transcript/TranscriptWordV1.swift`

## CLI
Run order (local-only):
- `MetaVisLab sensors ingest --input <movie.mov> --out <dir>`
- `MetaVisLab transcript generate --input <movie.mov> --out <dir>`
- `MetaVisLab diarize --sensors <dir>/sensors.json --transcript <dir>/transcript.words.v1.jsonl --out <dir>`

## Implementation Notes
- Engine: `Sources/MetaVisPerception/Diarization/SpeakerDiarizer.swift`
- CLI: `Sources/MetaVisLab/DiarizeCommand.swift`
- Transcript JSONL record type (shared contract): `Sources/MetaVisCore/Transcript/TranscriptWordV1.swift`
