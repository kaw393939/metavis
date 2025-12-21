# Architecture — Whisper Transcription CLI v1

## Reuse points
- Transcript schema + time conversion: Sprint 22.
- Caption emission: `CaptionSidecarWriter` (VTT/SRT) in Sources/MetaVisExport/Deliverables/SidecarWriters.swift.
- Export integration: `ProjectSession` already discovers sibling captions for single-source timelines in Sources/MetaVisSession/ProjectSession.swift.

## Components

### 1) `TranscriptCommand` (MetaVisLab)
- Parses args.
- Enforces large-asset policy consistent with other commands.
- Calls `WhisperCLITranscriber`.
- Writes artifacts.

### 2) `WhisperCLITranscriber` (MetaVisServices preferred)
- Builds a deterministic invocation to the external whisper tool.
- Parses its output into `TranscriptWord` records.
- Does not perform diarization.

## Audio extraction strategy
Prefer reuse of deterministic audio decoding already present in MetaVisIngest:
- Sources/MetaVisIngest/Audio/AudioSampleExtractor.swift

If whisper needs a WAV path, write a temp WAV using extracted PCM.
Avoid introducing a second audio decode stack unless required.

## Error handling
- Clear failures when whisper tool/model is not configured.
- Keep stdout/stderr logs in `--out` for debugging (raw tool output capture).

## Future extension
- Sprint 24 can post-process `transcript.words.v1.jsonl` + `sensors.json` to assign `speakerId/speakerLabel`.
