# Data Dictionary — Transcript Artifacts

## File: `transcript.words.v1.jsonl`

One JSON object per line.

### `TranscriptWord.v1`
- `schema` (string, required): must equal `transcript.word.v1`
- `wordId` (string, required): deterministic identifier
- `word` (string, required): token text
- `confidence` (number 0..1, required)
- `sourceTimeTicks` (integer, required): start time in 1/60000s ticks
- `sourceTimeEndTicks` (integer, required): end time in ticks
- `speakerId` (string|null, required): machine speaker ref
- `speakerLabel` (string|null, required): human label
- `timelineTimeTicks` (integer|null, required)
- `timelineTimeEndTicks` (integer|null, required)
- `clipId` (string|null, required)
- `segmentId` (string|null, required)

## File: `captions.vtt` / `captions.srt`
Produced via `CaptionCue` using existing writers.

### `CaptionCue`
- `startSeconds` (Double)
- `endSeconds` (Double)
- `text` (String)
- `speaker` (String?) — emits `<v Speaker>` in VTT

## Determinism rules
- Always sort words by (`sourceTimeTicks`, `sourceTimeEndTicks`, stable ordinal).
- No overlapping words for the same speaker are required in v1 (real transcripts can overlap).
