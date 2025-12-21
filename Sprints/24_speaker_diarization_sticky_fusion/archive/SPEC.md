# Spec — Speaker Diarization v1 (ECAPA‑TDNN + Sticky Fusion)

## Overview
Diarization assigns each transcript word a speaker identity suitable for interview/podcast editing.

This v1 is local-first and deterministic:
- It introduces an **on-device speaker embedding model** (ECAPA‑TDNN in CoreML) as the primary separation signal.
- It uses **clustering** (cosine similarity) to build time-local speaker identities.
- It uses existing sensor signals (face tracks) for **late fusion** (cluster → face co-occurrence).
- It retains the existing **Sticky Fusion heuristic** as a baseline / fallback when embeddings are unavailable.

## Inputs
- `sensors.json` (MasterSensors) produced by `MetaVisLab sensors ingest`.
- `transcript.words.v1.jsonl` produced by Sprint 23.
- Source movie path is read from `sensors.source.path` for local audio extraction.

## Outputs
- `transcript.words.v1.jsonl` with speaker fields populated.
- `captions.vtt` with `<v Speaker>` tags.
- `speaker_map.v1.json` describing deterministic label assignment.

## Speaker identity model
- `speakerId` is a machine identity:
  - primary: cluster identity mapped to a face track when co-occurrence is strong
    - if mapped: use `trackId` string from `MasterSensors.VideoSample.Face.trackId`
    - else: `OFFSCREEN`
  - (optional future) support unknown speaker IDs for audio-only clusters

- `speakerLabel` is a human-friendly label:
  - `T1`, `T2`, ... assigned deterministically by first appearance time.
  - `OFFSCREEN` stays literal.

## Stickiness rule (non-negotiable)
When multiple candidate speakers exist at a word time:
- Prefer keeping the previous speaker if it remains plausible.
- Only switch speakers if the new candidate is sufficiently stronger than the current speaker.
- Avoid flip-flopping on small dominance changes.

## Fusion rules

### Speech gating
- Prefer diarization inside `.speechLike` segments when present.
- Fallback: when ingest cannot classify speech (segments are `.unknown`), allow diarization inside any non-silence segment.

### Audio embeddings + clustering
- Extract mono PCM at 16kHz.
- Slice fixed windows (e.g. 3.0s with hop 0.5s).
- Run ECAPA‑TDNN to produce unit-normalized embeddings.
- Cluster online using cosine similarity.

### Late fusion: clusters → faces
- For each embedding window time, find dominant visible face (if any).
- For each cluster, compute co-occurrence $P(\text{face} \mid \text{cluster})$.
- Map cluster to a face track when co-occurrence exceeds a threshold (e.g. 0.8), otherwise `OFFSCREEN`.

### Word attribution
- For each word midpoint time:
  - find nearest embedding window cluster assignment
  - map cluster → speakerId (face track or OFFSCREEN)
  - apply stickiness/hysteresis across words

### Offscreen
- If speech-like (or gated-in) but no face mapping exists: mark `OFFSCREEN`.

## Determinism requirements
- Stable speakerLabel assignment order.
- Stable results given identical input sensors + transcript.

## Non-goals
- Speaker re-identification across long occlusions.
- True multi-speaker overlap handling.
- Network diarization.
