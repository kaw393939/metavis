# Sprint 24 — Architecture (Speaker Diarization + Sticky Fusion)
**Status:** In-progress (backbone implemented; contract hardening ongoing)
**Last updated:** 2025-12-21

## Goal
Produce deterministic, edit-grade speaker attribution at the **word level** by fusing:
- audio-first diarization (ECAPA‑TDNN embeddings + deterministic clustering)
- existing sensor identity primitives (face tracks/personId)
- a deterministic fallback (Sticky Fusion)

## Reuse Points (avoid drift)
- **Transcript words contract:** `TranscriptWordV1` (MetaVisCore)
- **Captions speaker tags:** `CaptionCue.speaker` + `CaptionSidecarWriter`
- **Sensors schema:** `MasterSensors` (MetaVisPerception)
- **Deterministic identity primitives from ingest:** stable `trackId` remap + `personId`
- **Governed confidence:** `ConfidenceRecordV1` + finite `ReasonCodeV1` (MetaVisCore)

## High-level Flow
1. **Ingest sensors** (face tracks + audioSegments) → `sensors.json`
2. **Generate transcript words** (Whisper) → `transcript.words.v1.jsonl` (speaker fields nil)
3. **Diarize** (this sprint) → populate `speakerId`/`speakerLabel` and emit sidecars

## Components

### 1) Audio embedding pipeline (primary path)
**Responsibility:** Convert audio windows into speaker embeddings deterministically.

Conceptual stages:
- `AudioWindowExtractor`:
  - takes the source audio track and produces fixed-size windows
  - deterministically pads/trims to a fixed duration
- `ECAPAEmbeddingExtractor`:
  - CoreML model wrapper
  - deterministic preprocessing (mono, fixed sample rate, fixed normalization)

Key invariants:
- Fixed input shapes (ANE-friendly)
- Stable windowing (no floating drift; derived from timebase + fixed hop)

### 2) Deterministic clustering
**Responsibility:** Assign each embedding window to a cluster deterministically.

Constraints:
- Stable ordering of windows
- Stable tie-breakers
- No randomness

Conceptual artifact (internal):
- `AudioClusterTimeline`: list of `(start,end,clusterId,clusterStats)`

### 3) Late fusion to faces (binding)
**Responsibility:** Map audio clusters to visual identities when confident.

Inputs:
- face track presence timeline from `MasterSensors.videoSamples[].faces[]`
- audio cluster timeline

Method (v1):
- compute co-occurrence between cluster activity and face presence
- bind cluster → `personId` (or `trackId`) when above threshold
- otherwise bind to `OFFSCREEN`

### 4) Word-level attribution
**Responsibility:** Fill `speakerId`/`speakerLabel` on transcript words.

Rules:
- Only assign speakers within `.speechLike` intervals (avoid hallucinating)
- Apply stickiness/hysteresis to prevent oscillation within an utterance
- Label assignment is stable by first appearance: `T1`, `T2`, …

### 5) Sticky Fusion fallback
**Responsibility:** Deterministic heuristic attribution without embeddings.

Inputs:
- face dominance + hysteresis
- `.speechLike` gating

When used:
- embedding model absent/unavailable
- explicit “fallback” mode

## Outputs (stable contract)
- `transcript.words.v1.jsonl` (same schema; speaker fields populated)
- `captions.vtt` (WebVTT voice tags)
- `speaker_map.v1.json` (speakerId → label)

Planned internal contract (edit-grade hardening):
- `identity.timeline.v1.json` (cluster lifecycle, bindings, OFFSCREEN spans, governed confidence)

## Confidence (mandate)
Sprint 24 must not invent ad-hoc confidence.

- Use `ConfidenceRecordV1` for attribution/binding confidence.
- Current gap: `TranscriptWordV1` does not carry `attributionConfidence`.
  - Options:
    - bump transcript word schema (e.g. `transcript.word.v2`), or
    - emit a dedicated attribution sidecar keyed by `wordId`.

## Where it lives
- Engine: `Sources/MetaVisPerception/Diarization/...`
- CLI: `Sources/MetaVisLab/DiarizeCommand.swift`
- Shared contracts: `Sources/MetaVisCore/Transcript/TranscriptWordV1.swift`

## What Sprint 24 consumes from Sprint 24a
- Governed confidence primitives: `ConfidenceRecordV1` / `ReasonCodeV1`
- Deterministic identity mapping in sensors ingest (`trackId` + `personId`)
- Deterministic warning segment semantics (no silent degrade)
