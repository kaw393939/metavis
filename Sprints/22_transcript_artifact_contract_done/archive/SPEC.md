# Spec — Transcript Artifact Contract v1

## Overview
A transcript is a **sidecar dataset** intended for:
- exact edit points (word-level timestamps)
- downstream AI planning (Gemini/local) without raw-media exposure
- exportable captions (VTT/SRT)

This sprint defines *schema + invariants* only.

## Canonical time
- **Ticks** are integer time units of **1/60000 second** (align with `MetaVisCore.Time`).
- Every word has:
  - `sourceTimeTicks` (start)
  - `sourceTimeEndTicks` (end)
  - `timelineTimeTicks` (optional, may be null until an edit exists)
  - `timelineTimeEndTicks` (optional)

### Conversion rule
- `ticks = round(seconds * 60000)` (documented; tests must enforce).
- `seconds = Double(ticks) / 60000.0`
- Non-finite seconds are rejected.

## Record format
- JSONL (`.jsonl`): **one JSON object per word**, UTF-8.
- File name: `transcript.words.v1.jsonl`

## `TranscriptWord.v1`
Required fields:
- `schema` = "transcript.word.v1"
- `wordId` (stable string; see below)
- `word` (string; already normalized to a single token)
- `confidence` (0..1; if unknown use `1.0` but still present)
- `sourceTimeTicks` (Int64)
- `sourceTimeEndTicks` (Int64)

Speaker fields:
- `speakerId` (string | null) — machine ID (e.g. face track UUID, or "OFFSCREEN", or "UNKNOWN_0")
- `speakerLabel` (string | null) — human-friendly label (e.g. "T1", "T2", "OFFSCREEN")

Timeline mapping fields (optional in v1; required once edits exist):
- `timelineTimeTicks` (Int64 | null)
- `timelineTimeEndTicks` (Int64 | null)
- `clipId` (string | null) — stable UUID if the word is mapped into a clip
- `segmentId` (string | null) — stable identifier for grouping words into higher-level segments

## `wordId` stability rule
`wordId` must be deterministic across reruns of the same transcription result.
Recommended v1: `w_<sourceTimeTicks>_<sourceTimeEndTicks>_<ordinalWithinSameRange>`

## Caption mapping contract
- `TranscriptWord.v1` can be deterministically grouped into `CaptionCue` records.
- Speaker is emitted into WebVTT using `<v Speaker>` (already supported).
- Caption writer/parsers are reused (do not reimplement VTT/SRT formatting).

## Non-goals
- Whisper/STT runtime.
- Diarization algorithm.
- EvidencePack builder.
