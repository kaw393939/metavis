# Sprint 24 — Data Dictionary (Diarization Artifacts)
**Status:** In-progress (backbone implemented; attribution confidence sidecar implemented)
**Last updated:** 2025-12-21

This document defines the versioned outputs produced by Sprint 24.

## 1) `transcript.words.v1.jsonl`
**Schema:** `transcript.word.v1` (record-per-line JSONL)

Diarization populates:
- `speakerId` (string?)
- `speakerLabel` (string?)

Notes:
- Sprint 24 does **not** change the v1 transcript word schema.
- When diarization cannot confidently assign a speaker, it must use explicit `OFFSCREEN` semantics (see below) rather than silently guessing.

### Required determinism rules
- For a given `(sensors.json, transcript.words.v1.jsonl, diarize options)`, the output must be identical.
- Speaker labels must be stable and assigned by first appearance: `T1`, `T2`, …

## 2) `captions.vtt`
**Format:** WebVTT

- Derived from transcript words grouped into cues.
- Uses voice tags: `<v T1>`, `<v OFFSCREEN>`, etc.

## 3) `speaker_map.v1.json`
**Schema:** `speaker_map.v1`

Purpose: provide a stable mapping from internal IDs to user-facing labels.

Fields:
- `schema`: string, must be `speaker_map.v1`
- `createdAt`: string (ISO-8601)
- `speakers`: array of:
  - `speakerId`: string
    - recommended: `personId` when bound, otherwise `OFFSCREEN`
  - `speakerLabel`: string (`T1`, `T2`, …, or `OFFSCREEN`)
  - `firstSeenTimeTicks`: integer (ticks)

Determinism rules:
- Assign labels by ascending `firstSeenSourceTimeTicks`.
- Break ties by lexical order of `speakerId`.
- `createdAt` must not introduce nondeterminism in contract outputs (CLI should write a fixed timestamp).

## 4) `OFFSCREEN` semantics
`OFFSCREEN` is a semantic identity state.

Requirements:
- `OFFSCREEN` has a stable `speakerId` (literal: `OFFSCREEN`).
- `OFFSCREEN` spans should be contiguous/stable (no flip-flopping within a short utterance).

## 5) Governed confidence (required by mandate)
Sprint 24 uses the shared confidence ontology from MetaVisCore:
- `ConfidenceRecordV1`
- `ReasonCodeV1` (finite, sorted)

### Implemented: attribution sidecar (minimal churn)
- File: `transcript.attribution.v1.jsonl`
- Record schema: `transcript.attribution.v1`
- Each record keyed by `wordId`:
  - `wordId`: string
  - `speakerId`: string?
  - `speakerLabel`: string?
  - `attributionConfidence`: `ConfidenceRecordV1`

Notes:
- This keeps `TranscriptWordV1` stable.
- Records are emitted in the same order as `transcript.words.v1.jsonl`.

### Deferred option: transcript schema bump
If/when consumers prefer a single file contract, introduce `transcript.word.v2` adding:
- `attributionConfidence: ConfidenceRecordV1`

## 6) Planned internal artifact: `identity.timeline.v1.json`
Not required for the current backbone, but required to reach “edit-grade” and to support Scene State.

Conceptual fields:
- clusters:
  - lifecycle: `bornAt`, `lastActiveAt`, `frozen`
  - deterministic merge decisions
  - governed confidence records + reason codes
- bindings:
  - cluster → person/face binding decisions (including `OFFSCREEN`)
  - explicit binding confidence
- attribution:
  - word-level assignments + confidence

This artifact becomes the canonical “identity spine” consumed by derived Scene State summaries.
