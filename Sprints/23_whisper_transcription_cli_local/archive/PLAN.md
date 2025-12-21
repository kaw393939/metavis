# Sprint 23 — Whisper Transcription CLI (Local)

## Goal
Provide a **local-first** transcription pipeline that outputs:
- `transcript.words.v1.jsonl` (word-level, tick-aligned)
- `*.captions.vtt` (speaker empty for now)

…and does so without changing Session/export behavior (exports already copy caption sidecars when present).

## Acceptance criteria
- New CLI command exists: `MetaVisLab transcript generate ...`
- Works on `Tests/Assets/VideoEdit/keith_talk.mov` (with `--allow-large`).
- Produces:
  - `transcript.words.v1.jsonl` (Sprint 22 schema)
  - `<stem>.captions.vtt` adjacent to the source OR inside an output dir with an explicit option to also write adjacent.
- Deterministic output ordering and stable IDs are enforced.
- Tests exist:
  - unit tests always-on (parsing, time/tick conversion)
  - integration test gated on `WHISPER_BIN`+`WHISPER_MODEL` (or equivalent)

## Reuse-first constraints (no drift)
- Use Sprint 22 transcript schema and conversion rules.
- Use existing caption writer (`CaptionSidecarWriter`) rather than reformatting VTT/SRT.
- Use existing audio extraction where available (`AudioSampleExtractor`) before introducing new ffmpeg-only paths.
- External dependency is treated like ffmpeg: invoked via `Process`, env-gated for tests.

## Existing code likely touched
- Sources/MetaVisLab/MetaVisLabMain.swift (register command)
- Sources/MetaVisLab/* (new command)
- Sources/MetaVisIngest/Audio/AudioSampleExtractor.swift (reuse)
- Sources/MetaVisCore (TranscriptWord type from Sprint 22)

## New code to add
- Sources/MetaVisLab/TranscriptCommand.swift (new)
- Sources/MetaVisServices/WhisperCLITranscriber.swift (optional, but preferred for testability)
- Tests/MetaVisServicesTests/WhisperCLITranscriberParsingTests.swift
- Tests/MetaVisServicesTests/WhisperCLITranscriberIntegrationTests.swift (skipped unless configured)

## Deterministic data strategy
- Unit tests use golden sample JSON emitted by a fixed whisper wrapper.
- Integration test can run on a short cut (e.g. `--max-seconds 30`) to keep runtime bounded.

## Docs
- Spec: archive/SPEC.md
- Architecture: archive/ARCHITECTURE.md
- Data dictionary: archive/DATA_DICTIONARY.md
- TDD plan: archive/TDD_PLAN.md
