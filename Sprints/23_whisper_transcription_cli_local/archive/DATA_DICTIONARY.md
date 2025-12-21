# Data Dictionary — Whisper Transcription CLI Outputs

## File: `transcript.words.v1.jsonl`
See Sprint 22 data dictionary for `TranscriptWord.v1`.

## File: `transcript.summary.v1.json`
- `schema` (string) = `transcript.summary.v1`
- `input` (string) — input file name (not full path if redaction is needed later)
- `durationSeconds` (number)
- `language` (string|null)
- `tool` (object)
  - `name` (string) — e.g. `whisper.cpp` or `faster-whisper`
  - `version` (string|null)
  - `model` (string) — model identifier/path
- `wordCount` (integer)

## File: `captions.vtt`
Produced via `CaptionSidecarWriter` using derived `CaptionCue`.

## Optional raw logs
- `whisper.stdout.txt`
- `whisper.stderr.txt`
Captured for debugging and provenance.
