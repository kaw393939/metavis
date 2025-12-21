# Spec — Whisper Transcription CLI v1 (Local)

## Overview
Add a local MetaVisLab tool that creates a word-level transcript sidecar for a movie file.

This sprint focuses on **local, offline** transcription only.

## Command
`MetaVisLab transcript generate`

### Inputs
- `--input <movie.mov>` (required)
- `--out <dir>` (required)
- `--allow-large` (required for large assets like keith_talk)

### Optional
- `--max-seconds <s>` limit transcription time range (default: full duration)
- `--start-seconds <s>` (default: 0)
- `--language <code>` (default: auto)
- `--write-adjacent-captions true|false` (default: true) — writes `<stem>.captions.vtt` next to the source to enable export auto-discovery

## External dependency contract
Transcription is done by invoking an external local tool (Whisper) via `Process`.

### Required environment
One of:
- `WHISPER_BIN` + `WHISPER_MODEL` (recommended)

The CLI must fail with a clear message if the tool is not installed.

## Outputs
In `--out`:
- `transcript.words.v1.jsonl` (Sprint 22 schema)
- `transcript.summary.v1.json` (small metadata: duration, model, language, wordCount)
- `captions.vtt` (derived from words; speaker unset)

If `--write-adjacent-captions=true`:
- write `<input_stem>.captions.vtt` next to the input movie.

## Determinism rules
- Stable ordering and stable wordId.
- Record the transcriber tool + model identifiers in `transcript.summary.v1.json`.
- Use the Sprint 22 seconds↔ticks conversion rule.

## Non-goals
- Diarization.
- Network calls.
- EvidencePack.
