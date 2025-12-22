# Sprint 24 — Speaker Diarization (ECAPA‑TDNN Pivot)

## Goal
Populate `speakerId/speakerLabel` on transcript words and emit caption sidecars with speaker tags, optimized for interviews and podcasts.

This sprint uses a **local, on-device diarization backbone**:
- ECAPA‑TDNN speaker embeddings (CoreML / ANE)
- deterministic clustering on CPU (cosine similarity)
- late fusion to Vision face tracks via co-occurrence

The previous Sticky Fusion heuristic remains as a Phase 0 baseline/fallback.

## Acceptance criteria
- New CLI exists: `MetaVisLab diarize ...` (or `transcript diarize ...`).
- Given `sensors.json` and `transcript.words.v1.jsonl`, produces:
  - `transcript.words.v1.jsonl` (speaker fields populated)
  - `captions.vtt` with `<v Speaker>` tags
  - `speaker_map.v1.json` (stable mapping from internal speakerIds to friendly labels)
- **Embedding diarization path** exists and is deterministic:
  - fixed window embedding extraction
  - online clustering using cosine similarity
  - cluster→face mapping using co-occurrence threshold
- **Stickiness policy** is applied at the word level to avoid oscillation.
- Deterministic outputs: stable ordering, stable speaker labels (`T1`, `T2`, ... by first appearance).

## Reuse-first constraints (no drift)
- Reuse `MasterSensors` as-is; do not add diarization fields to it in v1.
- Reuse `CaptionCue.speaker` + `CaptionSidecarWriter` for VTT output.
- Reuse deterministic face track IDs already produced by ingest.

## Existing code likely touched
- Sources/MetaVisLab/* (new command)
- Sources/MetaVisPerception/MasterSensors.swift (read-only consumption)
- Sources/MetaVisCore/Captions/* (TranscriptWord type from Sprint 22)

## New code to add
- Sources/MetaVisPerception/Diarization/Audio/* (audio extraction + embeddings + clustering)
- Sources/MetaVisPerception/Diarization/SpeakerDiarizer.swift (baseline heuristic)
- Sources/MetaVisLab/DiarizeCommand.swift (wires modes)
- Tests/MetaVisPerceptionTests/* (clusterer + fusion + diarizer contract tests)

## Deterministic data strategy
- Unit tests use synthetic sensors + synthetic transcript fixtures.
- Optional local integration tests run on real assets when Whisper is installed; embedding-based assertions are gated on an ECAPA model being configured.

## Docs
- Spec: archive/SPEC.md
- Architecture: archive/ARCHITECTURE.md
- Data dictionary: archive/DATA_DICTIONARY.md
- TDD plan: archive/TDD_PLAN.md
