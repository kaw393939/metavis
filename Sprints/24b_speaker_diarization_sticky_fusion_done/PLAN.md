# Sprint 24 — PLAN (Speaker Diarization + Sticky Fusion)
**Status:** DONE
**Last updated:** 2025-12-22

## Goal
Generate speaker-labeled, word-level transcripts suitable for interviews/podcasts by fusing:
- Whisper word timings
- sensors identity primitives (face tracks)
- on-device speaker embeddings (ECAPA‑TDNN → clustering)

## Non-negotiable mandate
1. Deterministic
2. Edit‑grade stable
3. Explicit about uncertainty (no silent guesses)

## What exists today (reality-based)
- Sticky Fusion heuristic diarizer exists (deterministic fallback).
- ECAPA‑TDNN embedding extraction + deterministic clustering exists in code and is the primary signal when enabled.
- CLI writes:
  - `transcript.words.v1.jsonl` (speaker fields populated)
  - `captions.vtt` (voice tags)
  - `speaker_map.v1.json`

See:
- `IMPLEMENTED.md`

## Acceptance criteria (Sprint 24 “ship”) 
- Deterministic diarization outputs for a fixed fixture set.
- Stable labeling (`T1`, `T2`, ...) and stable OFFSCREEN semantics.
- A small set of contract tests that prevent regressions.

## Closeout
- Output contracts are implemented and covered by contract tests.
- `OFFSCREEN` is treated as a first-class speaker ID.
- Governed word-level confidence is emitted via `transcript.attribution.v1.jsonl`.
- The identity spine artifact is emitted via `identity.timeline.v1.json`.

## Deliverables (docs)
- Architecture: `ARCHITECTURE.md`
- Data dictionary: `DATA_DICTIONARY.md`
- TDD plan: `TDD_PLAN.md`

## What Sprint 24 now gets “for free” from Sprint 24a
- Governed confidence primitives exist (`ConfidenceRecordV1` / finite `ReasonCodeV1`).
- Sensors ingest already emits deterministic IDs (`trackId` remap + stable `personId`) and deterministic warnings.

## CLI usage
Typical local flow:
- `MetaVisLab sensors ingest --input <movie.mov> --out <dir>`
- `MetaVisLab transcript generate --input <movie.mov> --out <dir>`
- `MetaVisLab diarize --sensors <dir>/sensors.json --transcript <dir>/transcript.words.v1.jsonl --out <dir>`
