# Data Dictionary — Speaker Diarization Outputs

## File: `speaker_map.v1.json`
- `schema` (string) = `speaker.map.v1`
- `speakers` (array)
  - `speakerId` (string) — machine ID (face track UUID string or `OFFSCREEN`)
  - `speakerLabel` (string) — `T1`, `T2`, ... or `OFFSCREEN`
  - `firstSeenSourceTimeTicks` (integer)

## File: `transcript.words.v1.jsonl`
Same as Sprint 22, but diarization populates:
- `speakerId`
- `speakerLabel`

## File: `captions.vtt`
- Derived from transcript words grouped into `CaptionCue`.
- `CaptionCue.speaker` uses `speakerLabel` (e.g. `T1`).

## Determinism rules
- Speaker label assignment is deterministic by ascending `firstSeenSourceTimeTicks`.
- When ties exist, break ties by stable `speakerId` lexical order.
